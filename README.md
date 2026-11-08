# k8s manage

Kubernetes クラスタの Cilium、コンテナレジストリ、Argo CD を Helmfile で管理する。

## Argo CD

Argo CD の設定は [values/argocd.yml](values/argocd.yml) で管理する。適用前に `kubectl config current-context` で対象クラスタを確認する。

### Google ログインの準備

Google Cloud で OAuth 同意画面と Web アプリケーション用 OAuth クライアントを作成する。承認済みリダイレクト URI には `https://argocd.navy1634.com/auth/callback` を登録する。テスト状態の外部アプリでは、ログインする Google アカウントをテストユーザーに追加する。

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

接続する端末で `argocd.navy1634.com` が Cilium Ingress の IP を解決するようにする。Ingress の IP は `kubectl -n kube-system get service cilium-ingress` で確認できる。

### インストールと接続

対象環境に合わせて `ENVIRONMENT` を指定し、Argo CD の release を適用する。

```sh
ENVIRONMENT=dev helmfile --selector name=argocd sync
kubectl -n argocd get pods
```

`https://argocd.navy1634.com` に接続する。接続 URL を変更する場合は、Google Cloud のリダイレクト URI と証明書も更新する。

Google アカウントの管理者権限は `argocd-rbac-cm` ConfigMap の `policy.admin.csv` で管理する。新規インストール後は次のコマンドで ConfigMap を開き、`data` に `policy.admin.csv` を追加して、管理者にするアカウントごとに `g, メールアドレス, role:admin` を設定する。

```sh
kubectl -n argocd edit configmap argocd-rbac-cm
```

管理者に指定していないアカウントには権限を付与しない。ローカル admin は無効にしているため、ConfigMap を復旧するには Kubernetes の管理権限が必要になる。
