# k8s manage

Kubernetes クラスタの Cilium、コンテナレジストリ、Argo CD、Prometheus/Grafana を Helmfile で管理する。

## 監視

Grafana の Kubernetes ダッシュボードで、Namespace ごとの Pod の CPU・メモリを確認できる。
接続先は `https://grafana.navy1634.com`。
Prometheus はデータを10日間保持し、`sandbox-server` 上の10GiローカルPVに保存する。
ローカルPVはノードに紐づくため、ノードやディスクの故障時にはデータを利用できない。
Pod の CPU・メモリ指標を取得するには、Prometheus から各ノードの kubelet へ TCP 10250 番で接続できる必要がある。

初回適用時は `monitoring` Namespace と `grafana-tls` Secret を作成する。
証明書には `grafana.navy1634.com` を含める。

```sh
# sandbox-server上でlocal PVのパスを作成し、Prometheus (UID 1000/GID 2000) に書込権限を与える
sudo install -d -o 1000 -g 2000 -m 0770 /var/lib/monitoring/prometheus

# Kubernetes 管理端末で実行
kubectl create namespace monitoring
kubectl -n monitoring create secret tls grafana-tls --cert=/path/to/cert.pem --key=/path/to/key.pem
ENVIRONMENT=dev helmfile --selector name=monitoring sync
```

## Argo CD

Argo CD の設定は [values/argocd.yml](values/argocd.yml) で管理する。
適用前に `kubectl config current-context` で対象クラスタを確認する。

### Google ログインの準備

Google Cloud で OAuth 同意画面と Web アプリケーション用 OAuth クライアントを作成する。
承認済みリダイレクト URI には `https://argocd.navy1634.com/auth/callback` を登録する。
テスト状態の外部アプリでは、ログインする Google アカウントをテストユーザーに追加する。

クライアント ID とクライアントシークレットを、次の形式で Git 管理外のファイルに保存する。`kubectl` の `--from-env-file` では値を引用符で囲まない。

```dotenv
GOOGLE_CLIENT_ID=取得したクライアントID
GOOGLE_CLIENT_SECRET=取得したクライアントシークレット
```

次の例では、ファイルを `/tmp/argocd-google.env` に保存している。ファイルと Kubernetes Secret は機密情報として扱う。

```sh
kubectl create namespace argocd
kubectl -n argocd create secret generic argocd-google-oauth --from-env-file=/tmp/argocd-google.env
kubectl -n argocd label secret argocd-google-oauth app.kubernetes.io/part-of=argocd
```

### HTTPS の準備

`argocd.navy1634.com` の証明書と秘密鍵を用意し、次のコマンドで `argocd-tls` Secret に登録する。パスは用意したファイルに合わせる。

```sh
kubectl -n argocd create secret tls argocd-tls --cert=/path/to/cert.pem --key=/path/to/key.pem
```

接続する端末で `argocd.navy1634.com` が Cilium Ingress の IP を解決するようにする。
Ingress の IP は `kubectl -n kube-system get service cilium-ingress` で確認できる。

### インストールと接続

対象環境に合わせて `ENVIRONMENT` を指定し、Argo CD の release を適用する。

```sh
ENVIRONMENT=prd helmfile --selector name=argocd sync
kubectl -n argocd get pods
```

### Helmfile の変更を prd へ自動同期

Argo CD の Pod が起動し、この設定を含む変更が `main` にマージされた後、Application を一度だけ登録する。

```sh
kubectl apply -f applications/prd/helmfile.yaml
```

`helmfile-prd` は `main` のリポジトリルートを Helmfile CMP で描画し、`ENVIRONMENT=prd` の全 release を Argo CD と同じクラスタへ自動同期して、手動変更を Git の状態へ戻す。prd の永続データを保護するため prune は無効にしている。Helmfile の定義から削除したリソースは自動削除されないため、削除が必要な場合はクラスタ上で別途行う。Registry の PVC には default StorageClass が必要で、ない場合は `values/registry-prd.yml` に `persistence.storageClassName` を指定する。prd の Registry は Ingress を作らず、クラスタ内部の ClusterIP で公開する。詳細は [Registry の永続化](charts/registry/README.md#永続化) を参照する。

Application の同期が始まった後は同じリソースを二重管理しないよう、`helmfile sync` を実行せず Git の変更を Argo CD に反映する。

別環境を追加するときは `applications/<環境名>/` に Application を作成し、`helmfile-<環境名>` と命名する。CMP の `ENVIRONMENT` と `destination.server` を対象環境に合わせて指定する。

`https://argocd.navy1634.com` に接続する。接続 URL を変更する場合は、Google Cloud のリダイレクト URI と証明書も更新する。

Google アカウントの管理者権限は `argocd-rbac-cm` ConfigMap の `policy.admin.csv` で管理する。
新規インストール後は次のコマンドで ConfigMap を開く。
`data` に `policy.admin.csv` を追加し、管理者にするアカウントごとに `g, メールアドレス, role:admin` を設定する。

```sh
kubectl -n argocd edit configmap argocd-rbac-cm
```

管理者に指定していないアカウントには権限を付与しない。ローカル admin は無効にしているため、ConfigMap を復旧するには Kubernetes の管理権限が必要になる。
