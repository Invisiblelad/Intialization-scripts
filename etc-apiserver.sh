#!/bin/bash
# ============================================================
#   etcd & API Server Troubleshooting Cheatsheet
#   Kubernetes Admin Reference
# ============================================================

# Shorthand — avoids repeating certs on every command
ETCDCTL="kubectl -n kube-system exec etcd-master -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key"


# ============================================================
# SECTION 1: etcd — HEALTH & STATUS
# ============================================================

# Endpoint health
$ETCDCTL endpoint health

# Endpoint status (DB size, leader, raft index)
$ETCDCTL endpoint status --write-out=table

# Performance test (disk latency + throughput)
$ETCDCTL check perf

# Member list (useful in multi-node HA clusters)
$ETCDCTL member list --write-out=table


# ============================================================
# SECTION 2: etcd — DATA OPERATIONS
# ============================================================

# List all keys in etcd
$ETCDCTL get / --prefix --keys-only

# Get a specific key (example: a pod)
$ETCDCTL get /registry/pods/default/mypod

# Count total number of keys
$ETCDCTL get / --prefix --keys-only | grep -v '^$' | wc -l


# ============================================================
# SECTION 3: etcd — MAINTENANCE (compact + defrag)
# ============================================================

# Step 1: Get current revision
REV=$($ETCDCTL endpoint status --write-out=json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])")
echo "Current revision: $REV"

# Step 2: Compact all old revisions up to current
$ETCDCTL compact $REV

# Step 3: Defrag — reclaim disk space from holes left by compaction
$ETCDCTL defrag

# Step 4: Verify DB size reduced
$ETCDCTL endpoint status --write-out=table


# ============================================================
# SECTION 4: etcd — ALARMS (quota exceeded)
# ============================================================

# List active alarms (NOSPACE = DB quota exceeded)
$ETCDCTL alarm list

# Disarm alarms after fixing the quota issue
$ETCDCTL alarm disarm


# ============================================================
# SECTION 5: etcd — BACKUP & RESTORE
# ============================================================

# Take a snapshot backup
$ETCDCTL snapshot save /tmp/etcd-backup.db

# Check snapshot integrity + metadata
$ETCDCTL snapshot status /tmp/etcd-backup.db --write-out=table


# ============================================================
# SECTION 6: etcd — HIGH DB SIZE RUNBOOK (step by step)
# ============================================================
#
# DB SIZE THRESHOLDS:
#   < 100MB    ✅ healthy
#   100MB–1GB  ⚠️  watch it
#   1GB–8GB    🔴 act now
#   > 8GB      💀 etcd refuses all writes (NOSPACE alarm fires)
#
# DECISION TREE:
#
#   DB size high?
#     │
#     ├─ STEP 1: Find what's bloated (events? pods? secrets?)
#     ├─ STEP 2: Clean up the Kubernetes objects causing the bloat
#     ├─ STEP 3: Compact old revisions
#     ├─ STEP 4: Defrag to reclaim disk space
#     ├─ STEP 5: Verify size dropped
#     └─ STEP 6: Prevent it from growing again (auto-compaction)
#
#   Still too big after all steps?
#     └─ STEP 7: Increase quota as last resort

# ----------------------------------------------------------
# STEP 1: CHECK — Find what is consuming the most space
# ----------------------------------------------------------

# See DB size right now
$ETCDCTL endpoint status --write-out=table

# Top key prefixes by count — tells you which resource type is bloated
# Common culprits: /registry/events, /registry/pods, /registry/secrets
$ETCDCTL get / --prefix --keys-only \
  | grep -v '^$' \
  | sed 's|/[^/]*$||' \
  | sort | uniq -c | sort -rn | head -20

# Check total key count
$ETCDCTL get / --prefix --keys-only | grep -v '^$' | wc -l

# Drill into a specific prefix (e.g. events are the top offender)
$ETCDCTL get /registry/events --prefix --keys-only | wc -l
$ETCDCTL get /registry/pods   --prefix --keys-only | wc -l
$ETCDCTL get /registry/secrets --prefix --keys-only | wc -l

# ----------------------------------------------------------
# STEP 2: CLEAN — Delete the bloat from Kubernetes
# ----------------------------------------------------------

# Delete succeeded pods (completed batch jobs etc.)
kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded

# Delete failed pods
kubectl delete pods --all-namespaces --field-selector=status.phase=Failed

# Delete old replicasets with 0 desired / 0 ready / 0 available
kubectl get rs --all-namespaces \
  | awk 'NR>1 && $3==0 && $4==0 && $5==0 {print $1, $2}' \
  | xargs -n2 kubectl delete rs -n

# Delete completed jobs
kubectl delete jobs --all-namespaces --field-selector=status.successful=1

# Delete all events (largest quick win — events pile up fast)
kubectl delete events --all-namespaces

# Delete unused configmaps (manual review first — don't blindly delete)
# kubectl get configmaps --all-namespaces | grep -v kube-system

# ----------------------------------------------------------
# STEP 3: COMPACT — Remove old revision history from etcd
# ----------------------------------------------------------

# Get the latest revision number
REV=$($ETCDCTL endpoint status --write-out=json \
  | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])")
echo "Compacting at revision: $REV"

# Compact — marks all revisions before $REV as reclaimable
$ETCDCTL compact $REV

# ----------------------------------------------------------
# STEP 4: DEFRAG — Physically reclaim the space on disk
# ----------------------------------------------------------

# Must run AFTER compact — compact marks space dead, defrag reclaims it
$ETCDCTL defrag

# ----------------------------------------------------------
# STEP 5: VERIFY — Confirm DB size has reduced
# ----------------------------------------------------------

$ETCDCTL endpoint status --write-out=table
# DB SIZE column should be noticeably smaller now

# ----------------------------------------------------------
# STEP 6: PREVENT — Enable auto-compaction so it never grows again
# ----------------------------------------------------------

# Edit etcd static pod manifest on the master node:
#   vi /etc/kubernetes/manifests/etcd.yaml
#
# Add these flags under the etcd container command:
#   --auto-compaction-mode=periodic
#   --auto-compaction-retention=1h     ← compact every hour automatically
#
# kubelet will auto-restart etcd when you save the file

# ----------------------------------------------------------
# STEP 7: LAST RESORT — Increase quota if DB is still too large
# ----------------------------------------------------------

# Only do this if you genuinely need more space temporarily
# while you work on permanent cleanup
#
# Edit: vi /etc/kubernetes/manifests/etcd.yaml
# Add/update flag:
#   --quota-backend-bytes=8589934592   # increase to 8GB
#
# After increasing quota, disarm the NOSPACE alarm:
$ETCDCTL alarm disarm


# ============================================================
# SECTION 7: API Server — HEALTH & STATUS
# ============================================================

# Basic health endpoints
kubectl get --raw /healthz
kubectl get --raw /readyz
kubectl get --raw /livez

# Component statuses (scheduler, controller-manager, etcd)
kubectl get componentstatuses

# API server pod status
kubectl get pod kube-apiserver-master -n kube-system -o wide

# API server logs
kubectl logs -n kube-system kube-apiserver-master --tail=100

# Filter logs for errors only
kubectl logs -n kube-system kube-apiserver-master --tail=100 | grep -i error

# Filter logs for slow/timeout warnings
kubectl logs -n kube-system kube-apiserver-master --tail=100 | grep -i "slow\|timeout\|took"


# ============================================================
# SECTION 8: API Server — METRICS
# ============================================================

# Inflight requests — should be well below 200 (mutating) / 400 (readOnly)
kubectl get --raw /metrics | grep apiserver_current_inflight_requests

# Request latency by resource + verb (look for high values)
kubectl get --raw /metrics | grep apiserver_request_duration_seconds_sum | grep -v '#'

# Total requests by resource + verb + response code (find hot paths)
kubectl get --raw /metrics | grep apiserver_request_total | grep -v '#' \
  | sort -t' ' -k2 -rn | head -20

# Request errors — non 2xx response codes
kubectl get --raw /metrics | grep apiserver_request_total | grep -v '#' \
  | grep -v ' 2[0-9][0-9] '

# Long-running watch connections currently open
kubectl get --raw /metrics | grep apiserver_longrunning_requests

# Resource usage of API server pod (needs metrics-server)
kubectl top pod kube-apiserver-master -n kube-system


# ============================================================
# SECTION 9: API Server — AUDIT & EVENTS
# ============================================================

# All cluster events sorted by most recent
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Warning events only
kubectl get events --all-namespaces --field-selector=type=Warning


# ============================================================
# SECTION 10: API Server — SLOW RESPONSE RUNBOOK (step by step)
# ============================================================
#
# DECISION TREE — work top to bottom, stop when you find the cause:
#
#   API slow?
#     │
#     ├─ STEP 1: Confirm API is actually slow (latency metrics)
#     ├─ STEP 2: Check if etcd is the bottleneck
#     ├─ STEP 3: Check inflight request count (overload?)
#     ├─ STEP 4: Find which resource/verb is slowest
#     ├─ STEP 5: Check for rogue controllers hammering the API
#     ├─ STEP 6: Check API server resource usage (CPU/memory)
#     └─ STEP 7: Check API server logs for slow handler warnings

# ----------------------------------------------------------
# STEP 1: CONFIRM — Is the API actually slow right now?
# ----------------------------------------------------------

# Basic health check — if this is slow, API is definitely struggling
time kubectl get --raw /healthz
time kubectl get nodes

# Check request duration — look for large values (seconds, not ms)
kubectl get --raw /metrics \
  | grep apiserver_request_duration_seconds_sum \
  | grep -v '#' \
  | sort -t' ' -k2 -rn \
  | head -20

# ----------------------------------------------------------
# STEP 2: CHECK ETCD — Is etcd the root cause?
# ----------------------------------------------------------

# Watch raft index live — APPLIED INDEX must equal RAFT INDEX
# If APPLIED lags behind → etcd is overloaded
watch -n 2 '$ETCDCTL endpoint status --write-out=table'

# Test etcd disk performance — slowest request should be < 10ms
$ETCDCTL check perf
# PASS: Slowest request took 0.008s  ✅
# FAIL: Slowest request took 0.250s  ❌ disk I/O is your problem

# Check etcd disk I/O on the master node
iostat -xz 1 5         # look for high %await on the etcd disk
ioping -c 10 /var/lib/etcd  # should be < 10ms per write

# ----------------------------------------------------------
# STEP 3: CHECK LOAD — Is the API server overloaded?
# ----------------------------------------------------------

# Inflight requests — limits are 200 mutating / 400 readOnly
# If you're near those limits, API will start throttling
kubectl get --raw /metrics | grep apiserver_current_inflight_requests

# Watch inflight requests live
watch -n 2 "kubectl get --raw /metrics | grep apiserver_current_inflight_requests"

# Count open watch/long-running connections
kubectl get --raw /metrics | grep apiserver_longrunning_requests

# ----------------------------------------------------------
# STEP 4: FIND — Which resource or verb is slowest?
# ----------------------------------------------------------

# Top slow resource+verb combinations by cumulative latency
kubectl get --raw /metrics \
  | grep apiserver_request_duration_seconds_sum \
  | grep -v '#' \
  | awk '{print $2, $1}' \
  | sort -rn \
  | head -15

# Total request volume — find who is sending the most requests
kubectl get --raw /metrics \
  | grep apiserver_request_total \
  | grep -v '#' \
  | sort -t' ' -k2 -rn \
  | head -20

# Request errors — non 2xx responses (signs of cascading failures)
kubectl get --raw /metrics \
  | grep apiserver_request_total \
  | grep -v '#' \
  | grep -v ' 2[0-9][0-9] '

# ----------------------------------------------------------
# STEP 5: FIND — Is a rogue controller/operator spamming the API?
# ----------------------------------------------------------

# Check which namespaces have the most activity
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -30

# Warning events only — often reveals crashlooping controllers
kubectl get events --all-namespaces --field-selector=type=Warning

# Find pods doing excessive API calls (look for controller pods)
kubectl top pods --all-namespaces --sort-by=cpu | head -20

# Check kube-controller-manager logs for reconcile storms
kubectl logs -n kube-system kube-controller-manager-master --tail=50 \
  | grep -i "error\|slow\|timeout\|requeue"

# ----------------------------------------------------------
# STEP 6: CHECK RESOURCES — Is the API server starved for CPU/RAM?
# ----------------------------------------------------------

# CPU and memory of API server pod (needs metrics-server)
kubectl top pod kube-apiserver-master -n kube-system

# Node-level resources on master
kubectl top node

# Check if API server is OOMKilled or restarting
kubectl describe pod kube-apiserver-master -n kube-system \
  | grep -A 5 "Last State\|Restart Count\|OOMKilled"

# ----------------------------------------------------------
# STEP 7: LOGS — Find slow handler warnings in API server logs
# ----------------------------------------------------------

# Slow request warnings (Kubernetes logs these automatically)
kubectl logs -n kube-system kube-apiserver-master --tail=200 \
  | grep -i "slow\|timeout\|took\|deadline"

# Authentication/authorization errors causing delays
kubectl logs -n kube-system kube-apiserver-master --tail=200 \
  | grep -i "authn\|authz\|forbidden\|unauthorized"

# TLS / certificate errors
kubectl logs -n kube-system kube-apiserver-master --tail=200 \
  | grep -i "tls\|cert\|x509\|expired"

# Full error scan
kubectl logs -n kube-system kube-apiserver-master --tail=200 \
  | grep -i "error\|warn\|fail" \
  | tail -30

# ----------------------------------------------------------
# SUMMARY: What each symptom points to
# ----------------------------------------------------------
#
#  SYMPTOM                              ROOT CAUSE
#  ─────────────────────────────────────────────────────────
#  check perf FAIL / high disk await  → etcd disk I/O slow (move to SSD)
#  RAFT INDEX ≠ APPLIED INDEX          → etcd overloaded
#  DB SIZE > 1GB                       → run compact + defrag
#  inflight_requests near 200/400      → too many API clients, throttling
#  one resource has huge latency_sum   → specific controller spamming API
#  API pod CPU/RAM maxed out           → increase API server resources
#  OOMKilled in describe               → increase memory limits
#  cert/tls errors in logs             → certificate expired, renew it
#  ─────────────────────────────────────────────────────────


# ============================================================
# QUICK REFERENCE CARD
# ============================================================
#
#  TASK                            COMMAND
#  ─────────────────────────────────────────────────────────
#  etcd healthy?                → endpoint health
#  etcd size + leader?          → endpoint status --write-out=table
#  etcd disk fast enough?       → check perf
#  etcd raft lag?               → watch endpoint status (INDEX == APPLIED?)
#  etcd too big?                → Section 6 runbook
#  etcd quota exceeded?         → alarm list → alarm disarm
#  etcd backup?                 → snapshot save
#  ─────────────────────────────────────────────────────────
#  API healthy?                 → kubectl get --raw /healthz
#  API slow?                    → Section 10 runbook
#  API overloaded?              → metrics | grep inflight_requests
#  API errors?                  → logs | grep error
#  API resource hog?            → metrics | grep request_total
#  API OOMKilled?               → describe pod | grep OOMKilled
#  ─────────────────────────────────────────────────────────
