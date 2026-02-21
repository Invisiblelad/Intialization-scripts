This script will deploy a kubernetes cluster.

The master-script.sh should be run on master node and the worker-script.sh should be run on worker node.


Once the script execution is done.A kubeadm join command will generate.Copy it and add it to worker node.

Then you need to add network either flanner or calico


# 🔥 Kubernetes Deep Debugging Guide (Full Commands Reference)

This document contains EVERYTHING discussed:

✔ ServiceAccount tokens\
✔ RBAC authorization & curl testing\
✔ Projected Volumes (tmpfs)\
✔ Overlay filesystem\
✔ Inodes & stat command\
✔ tcpdump traffic capture\
✔ Detecting pods calling API server\
✔ NetworkPolicy blocking\
✔ Caret (\^), shell variables, and command syntax explanation

This is written as a practical DevOps command reference.

------------------------------------------------------------------------

# 1️⃣ Enter Pod Shell

``` bash
kubectl exec -it nginx-677db6c969-4schv -- sh
```

------------------------------------------------------------------------

# 2️⃣ ServiceAccount Files

``` bash
ls /run/secrets/kubernetes.io/serviceaccount
```

Example Output:

    ca.crt
    namespace
    token

------------------------------------------------------------------------

# 3️⃣ Shell Syntax (Caret, Backslash, Variables)

Store token:

``` bash
TOKEN=$(cat /run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```
# Secure (verify with CA)
curl --cacert $CACERT -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api

List namespace pods using API (secure)
curl --cacert $CACERT -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/default/pods

Example:

``` bash
curl -sSk \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api
```

------------------------------------------------------------------------

# 4️⃣ Call Kubernetes API

``` bash
curl -sSk \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api
```

Example Output:

``` json
{
  "kind": "APIVersions",
  "versions": ["v1"]
}
```

------------------------------------------------------------------------

# 5️⃣ RBAC Forbidden Example

``` bash
curl -sSk \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/default/pods
```

Expected:

    403 Forbidden

------------------------------------------------------------------------

# 6️⃣ Check Permissions

``` bash
kubectl auth can-i list pods \
--as system:serviceaccount:default:default
```

Example:

    no

------------------------------------------------------------------------

# 7️⃣ Projected Volume (tmpfs)

``` bash
mount | grep serviceaccount
df -h
```

Example:

    tmpfs on /run/secrets/kubernetes.io/serviceaccount type tmpfs

------------------------------------------------------------------------

# 8️⃣ Overlay Filesystem

``` bash
df -h
```

Example:

    overlay 59G /

------------------------------------------------------------------------

# 9️⃣ Inode Details

``` bash
stat /run/secrets/kubernetes.io/serviceaccount/token
```

Example:

    Inode: 123456
    Modify: Feb 21

------------------------------------------------------------------------

# 🔟 Find API Server IP

``` bash
getent hosts kubernetes.default.svc
```

Example:

    10.43.0.1 kubernetes.default.svc

------------------------------------------------------------------------

# 1️⃣1️⃣ tcpdump Debugging

``` bash
kubectl run debug --rm -it --image=nicolaka/netshoot -- bash
```

Capture:

``` bash
tcpdump -i any host kubernetes.default.svc
```

Generate traffic:

``` bash
curl -k https://kubernetes.default.svc/version
```

------------------------------------------------------------------------

# 1️⃣2️⃣ Detect Pods Talking to API Server

``` bash
sudo ss -tnp | grep 10.43.0.1
kubectl get pods -A -o wide | grep <POD_IP>
```

------------------------------------------------------------------------

# 1️⃣3️⃣ NetworkPolicy Example

``` yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-egress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
```

Apply:

``` bash
kubectl apply -f deny-egress.yaml
```

Test:

``` bash
curl -k https://kubernetes.default.svc/version
```

Expected:

    Connection timeout

------------------------------------------------------------------------

# 1️⃣4️⃣ Extra Debug Commands

``` bash
env | grep KUBERNETES
ip a
ss -tuna
netstat -plant
```

------------------------------------------------------------------------

# 1️⃣5️⃣ Security Notes

-   Avoid using default ServiceAccount
-   Use minimal RBAC
-   Block API server via NetworkPolicy if not required
-   Tokens rotate automatically
