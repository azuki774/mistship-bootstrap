# Auth0 OIDC for Kubernetes API

`mistship` の control plane は、Kubernetes API Server で Auth0 OIDC 認証を受ける前提です。
この repo では control plane 用 TalOS config に OIDC 設定を埋め込み、`kubelogin` で取った ID Token を `kubectl` から使えるようにします。

## Control plane に入れている設定

`patches/controlplane.yaml` で次の OIDC 設定を `kube-apiserver` へ渡します。

- issuer: `https://azk.jp.auth0.com/`
- client ID: `x33YdbDxOrVfflDOdNmyLy6wCDgWCPGN`
- username claim: `email`
- groups claim: `https://mistship-cp.azuki.blue/groups`
- groups prefix: `-`

この構成は Auth0 の ID Token を受ける前提です。
`urn:mistship:kubernetes` は API audience として `kubelogin` の認可要求に使いますが、API Server の `oidc-client-id` には使いません。

## kubeconfig の例

`kubectl` 側では `kubelogin` を使います。

```yaml
users:
  - name: auth0-mistship
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        command: kubelogin
        args:
          - get-token
          - --oidc-issuer-url=https://azk.jp.auth0.com/
          - --oidc-client-id=x33YdbDxOrVfflDOdNmyLy6wCDgWCPGN
          - --oidc-extra-scope=openid
          - --oidc-extra-scope=profile
          - --oidc-extra-scope=email
          - --oidc-extra-scope=offline_access
          - --oidc-auth-request-extra-params=audience=urn:mistship:kubernetes
```

既存の cluster context にこの user を紐付けるか、OIDC 用の別 user/context を追加して使います。

## 最初の確認方法

最初は group bind ではなく user 直 bind で確認します。
username claim は `email` なので、最初の疎通確認はそのメールアドレスに対する `ClusterRoleBinding` を使います。

例:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: auth0-azuki774-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: azuki774s@gmail.com
```

この binding は恒久運用の最終形ではなく、OIDC 認証と username claim の確認用です。

## Groups claim の注意

group ベースへ移るときは、Auth0 側で `https://mistship-cp.azuki.blue/groups` claim に値が入っていることを先に確認します。

参照元メモの前提では、Auth0 Action は次の優先順で group claim を作ります。

1. `user.app_metadata.kubernetes_groups`
2. `event.authorization.roles`

ただし `user.app_metadata.kubernetes_groups` が空配列でも存在すると、roles へフォールバックしません。
group ベース RBAC に移る前に、対象 user の claim 内容を必ず確認してください。
