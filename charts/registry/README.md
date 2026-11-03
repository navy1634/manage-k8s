# Registry

Registry は Helmfile から `charts/registry` を適用して管理する。

## 永続化

dev では 1 台構成を前提にしているため、chart で静的 PV を作成する。PV は `hostPath: /var/lib/registry` を使い、`values/registry-dev.yml` の `persistentVolume.nodeName` で対象ノードに固定する。

prd では chart で PV を作成しない。PVC だけを作成し、実際の PV はクラスタの StorageClass による動的プロビジョニングに任せる。複数台構成で hostPath の静的 PV を使うと、Pod が別ノードへ移動したときに registry のデータを参照できなくなるため。

prd では default StorageClass が存在するか、`values/registry-prd.yml` で `persistence.storageClassName` を明示する必要がある。

## HTTPS

dev では Cilium Ingress で TLS を終端し、`registry.local` でレジストリを公開する。証明書と秘密鍵はリポジトリへ追加せず、mkcert で作成したファイルから `registry-tls` Secret を作成する。

Ingress の外部 IP は現在 `192.168.0.242` なので、push する端末で `registry.local` がその IP を解決するように設定する。Linux または WSL では `/etc/hosts` に次の行を追加する。

```text
192.168.0.242 registry.local
```

Namespace を先に作成し、mkcert の証明書を Secret として登録してから dev 環境を適用する。

```sh
kubectl create namespace registry --dry-run=client -o yaml | kubectl apply -f -
kubectl -n registry create secret tls registry-tls \
  --cert=/mnt/c/Users/kny16/.cert/registry.local.pem \
  --key=/mnt/c/Users/kny16/.cert/registry.local-key.pem \
  --dry-run=client -o yaml | kubectl apply -f -
ENVIRONMENT=dev helmfile sync --selector name=registry
```

証明書を更新するときは、同じ `create secret` コマンドを再実行してから `ENVIRONMENT=dev helmfile sync --selector name=registry` を実行する。

Docker Engine から接続する端末では、mkcert の CA `/mnt/c/Users/kny16/AppData/Local/mkcert/rootCA.pem` を Docker の信頼ストアへ `ca.crt` として登録する。Linux または WSL の Docker Engine では、通常 `/etc/docker/certs.d/registry.local/ca.crt` に配置する。

登録後、次のようにログインして push する。

```sh
docker login registry.local
docker push registry.local/<repository>:<tag>
```

## Kubernetes node の containerd

dev node では `containerd/dev/certs.d/registry.local:5000/hosts.toml` を `/etc/containerd/certs.d/registry.local:5000/hosts.toml` として配置する。この設定で `registry.local:5000` の image 参照を sandbox-server の `192.168.0.100:5000` へ送る。

containerd の CRI plugin が registry host 設定を読むよう、`/etc/containerd/config.toml` の registry 設定に次を指定する。

```toml
[plugins."io.containerd.cri.v1.images".registry]
  config_path = "/etc/containerd/certs.d"
```

`config.toml` を更新した後は containerd を再起動し、有効な `config_path` を確認する。

```sh
sudo systemctl restart containerd
sudo containerd config dump | grep -A1 -B1 'io.containerd.cri.v1.images.*registry'
```
