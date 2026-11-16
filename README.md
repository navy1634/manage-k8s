# manage_k8s

Kubernetes クラスタの基盤コンポーネントを Helmfile と Terraform で管理するリポジトリです。
Helmfile はクラスタ内の release を管理し、Terraform は Grafana dashboard を管理します。

## 管理対象と設定場所

| 領域 | 管理内容と設定場所 |
| --- | --- |
| ネットワーク | Cilium は `values/cilium.yml`、LoadBalancer は `charts/cilium-lb/` |
| GitOps | Argo CD は `values/argocd.yml`、prd Application は `applications/prd/helmfile.yaml` |
| 監視 | Prometheus/Grafana は `values/monitoring.yml`、`values/grafana.yml`、`values/prometheus.yml` |
| Grafana ダッシュボード | Terraform root は `terraform/grafana/env/prd/` |
| Registry chart | `charts/registry/` |
| Registry dev values | `values/registry-dev.yml` |
| Registry prd values | `values/registry-prd.yml` |
| Tailscale Operator | `values/tailscale-operator.yml` |
| Tailscale Connector / DNS resolver | `charts/tailscale-connector/`、`charts/tailscale-dns/` |

Registry の永続化と HTTPS は [Registry README](charts/registry/README.md) を参照してください。
このリポジトリが管理する Tailscale の範囲は Kubernetes 側のリソースです。
Tailnet 全体の policy や DNS 設定はここでは管理しません。

## 環境と Kubernetes context

Helmfile は `dev` または `prd` を環境名として受け取ります。
環境名は `values/registry-<環境名>.yml` の選択に使います。
環境名を指定しても Kubernetes context は切り替わりません。
適用先は `kubectl` の現在の context で決まります。

Argo CD の prd Application は [applications/prd/helmfile.yaml](applications/prd/helmfile.yaml) にあります。
Grafana dashboard 用の Terraform root は `terraform/grafana/env/prd/` にあります。
Terraform の version は [terraform/mise.toml](terraform/mise.toml) で管理します。

## 描画と適用

ルートの [mise.toml](mise.toml) は Helm、Helmfile、kubectl の version を固定しています。
初回は次のコマンドで必要なツールを用意し、適用先を確認してください。

```sh
mise install
kubectl config current-context
```

変更を確認するときは Helmfile の manifest を描画します。
クラスタへ反映するときは、描画内容と context を確認してから apply してください。

```sh
mise run render prd
mise run apply prd
```

`mise run apply <環境名>` はルート Helmfile の全 release を同期します。
環境名に `dev` を指定すると、Registry の dev 用 values を使います。
適用先は Kubernetes context で決まり、環境名では切り替わりません。
適用前に `kubectl config current-context` で必ず確認してください。

## 初回導入の準備

初回適用の前に、各 release が参照する Namespace と Secret を用意してください。
credential の値と証明書の秘密鍵は Git に追加しないでください。
Tailscale Operator には `tailscale` namespace の `operator-oauth` Secret が必要です。

### 監視

Prometheus はデータを10日間保持し、`sandbox-server` に接続した local PV を使います。
ノードまたはディスクが故障すると、保存データを利用できなくなります。
新しいクラスタでは、まず `sandbox-server` 上にデータ用ディレクトリを作成します。

```sh
sudo install -d -o 1000 -g 2000 -m 0770 /var/lib/prometheus
```

Grafana は Google OAuth でログインします。
Google Cloud で Web application 用 OAuth クライアントを作成してください。
承認済み JavaScript 生成元は `https://grafana.navy1634.com` にします。
承認済み redirect URI は `https://grafana.navy1634.com/login/google` にします。
OAuth 同意画面がテスト状態の場合は、ログインする Google アカウントをテストユーザーに追加します。
次の3つのキーを含む `grafana-google-oauth` Secret を `monitoring` namespace に作成します。
`GOOGLE_ROLE_ATTRIBUTE_PATH` には、Grafana に設定する role mapping expression を指定します。
ファイルは `/tmp/grafana-google.env` に保存する例です。
`kubectl --from-env-file` では値を引用符で囲みません。

```dotenv
GOOGLE_CLIENT_ID=<client-id>
GOOGLE_CLIENT_SECRET=<client-secret>
GOOGLE_ROLE_ATTRIBUTE_PATH=<role-mapping-expression>
```

Grafana 証明書には `grafana.navy1634.com` を含めてください。
Kubernetes 管理端末で Namespace、OAuth Secret、TLS Secret を作成します。

```sh
kubectl create namespace monitoring
kubectl -n monitoring create secret generic grafana-google-oauth \
  --from-env-file=/tmp/grafana-google.env
kubectl -n monitoring create secret tls grafana-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem
```

`values/grafana.yml` は Secret の3キーを必須参照します。
必須 Secret またはいずれかのキーがないと、Kubernetes は Grafana のコンテナを起動しません。
Helmfile は最大600秒待ち、`atomic: true` により失敗した初回 install を削除し、upgrade を前の状態へ戻します。

### Argo CD

Google Cloud で Web アプリケーション用 OAuth client を作成します。
承認済み redirect URI は `https://argocd.navy1634.com/auth/callback` です。
OAuth 同意画面がテスト状態の場合は、ログインする Google アカウントをテストユーザーに追加します。
OAuth client の ID と secret は Git 管理外のファイルに保存してください。
`kubectl --from-env-file` では値を引用符で囲みません。

```dotenv
GOOGLE_CLIENT_ID=<client-id>
GOOGLE_CLIENT_SECRET=<client-secret>
```

次の例では、そのファイルを `/tmp/argocd-google.env` に保存しています。
Argo CD の証明書には `argocd.navy1634.com` を含めてください。

```sh
kubectl create namespace argocd
kubectl -n argocd create secret generic argocd-google-oauth \
  --from-env-file=/tmp/argocd-google.env
kubectl -n argocd label secret argocd-google-oauth \
  app.kubernetes.io/part-of=argocd
kubectl -n argocd create secret tls argocd-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem
```

Argo CD の local admin は無効です。
管理者の割り当ては `argocd-rbac-cm` ConfigMap の `data.policy.admin.csv` で行います。
管理者にする Google アカウントごとに `g, <email>, role:admin` を設定してください。
ConfigMap は次のコマンドで編集できます。

```sh
kubectl -n argocd edit configmap argocd-rbac-cm
```

## Argo CD での自動デプロイ

Argo CD の Pod が起動してから Application を登録します。
Application は初回に一度だけ適用します。

```sh
kubectl apply -f applications/prd/helmfile.yaml
```

`helmfile-prd` は `main` のルート Helmfile を `ENVIRONMENT=prd` で描画します。
Argo CD と同じクラスタへ自動同期します。
Application は self-heal を有効にし、prune を無効にしています。
クラスタ上の手動変更は Git の状態へ戻ります。
Helmfile から削除したリソースは自動削除されません。
削除が必要な場合はクラスタ上で別途対応します。
