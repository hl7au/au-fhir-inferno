# Validator Startup Optimization

## Changes Made

### 1. Persistent Caches (Two Separate Caches)

StatefulSet automatically creates per-pod persistent volumes using `volumeClaimTemplates`.

#### Package Cache
- **Created by**: volumeClaimTemplates in StatefulSet
- **Mount**: `/home/ktor/.fhir/packages` with `subPath: packages`
- **SubPath**: Avoids EXT4 `lost+found` directory that causes initialization errors
- **Impact**: Each pod gets its own cache, reused across pod restarts
- **Storage**: 5Gi EBS gp3-encrypted (ReadWriteOnce per pod)

#### Terminology Cache
- **Created by**: volumeClaimTemplates in StatefulSet
- **Mount**: `/tmp/default-tx-cache` with `subPath: cache`
- **SubPath**: Avoids EXT4 `lost+found` directory that causes initialization errors
- **Impact**: Each pod caches its own terminology validation results
- **Storage**: 2Gi EBS gp3-encrypted (ReadWriteOnce per pod)

### 2. Health Probes
- **Startup Probe**: Allows up to 5 minutes for initial package downloads
- **Readiness Probe**: Ensures traffic only routes to ready validators
- **Liveness Probe**: Restarts unhealthy pods

### 3. Resource Configuration (Optimized)
- **Memory**: 2.5Gi request / 3Gi limit (optimized - auto heap ~2.4Gi via MaxRAMPercentage=79)
- **CPU**: 1000m request / 2000m limit (4x increase to eliminate CPU throttling)
- **Java Heap**: Auto-calculated at 79% of container memory limit
- **Savings**: 1Gi memory per pod (2Gi total), while fixing CPU bottleneck

### 4. StatefulSet Configuration
- **Changed**: Deployment → StatefulSet
- **Replicas**: 2 (each pod gets its own persistent cache)
- **Storage**: Using gp3-encrypted EBS volumes (ReadWriteOnce per pod)
- **Updates**: Rolling updates with zero downtime
- **Security**: fsGroup: 1000 ensures volumes are writable by ktor user
- **Benefits**: Each pod maintains its own cache, survives restarts

## Expected Performance Improvements

### First Deployment (With 2 Replicas)
- Each pod downloads packages to its own cache
- **Both pods download in parallel** (total cluster time: ~30-60 seconds with CPU optimization)
- Each pod: ~30-60 seconds to download and start (vs 2-3 min with CPU throttling)
- **No traffic** routed until each pod is truly ready (health probes)

### Subsequent Restarts (Per Pod)
- **~10-15 seconds** instead of 2+ minutes (packages already cached)
- Only JVM startup and context initialization needed
- **This is where you'll see the biggest improvement!**

### Rolling Updates
- ✅ **Zero downtime**: Old pod stays running while new pod starts
- New pod gets a fresh PVC, downloads packages (~30-60 sec with optimized CPU)
- After new pod is ready, old pod terminates
- Much faster than before due to CPU optimization

### Performance Impact of Optimizations
**Before (CPU throttled):**
- Load average: 3.00 on 0.5 CPU → severe throttling
- First deployment: ~2-3 minutes per pod
- Memory: 1.7Gi used of 4Gi limit (43% utilization)

**After (optimized):**
- CPU: 2.0 available (4x increase) → no throttling
- First deployment: ~30-60 seconds per pod (4-6x faster)
- Memory: 2.5Gi/3Gi (better utilization, 1Gi savings per pod)

## Deployment

The configuration is ready to deploy with your existing gp3-encrypted storage class:

```bash
helm upgrade inferno ./infra/helm/inferno \
  -f values.yaml \
  -n <your-namespace>
```

### Storage Configuration
- Uses `gp3-encrypted` (your default EBS storage class)
- **Per-pod PVCs**: Each of 2 pods gets 5Gi package cache + 2Gi terminology cache
- Total storage: 14Gi (7Gi per pod × 2 pods)
- PVCs automatically created/managed by StatefulSet
- PVCs persist even when pods are deleted (survive restarts)

### Scaling
- **Scale up**: New pods download their own packages on first start
- **Scale down**: PVCs remain (can be manually deleted if needed)
- Pods are named `validator-api-0`, `validator-api-1`, etc.

## Verification

After deployment, check startup time:
```bash
# Watch both pods startup
kubectl logs -f statefulset/validator-api -n <namespace> --all-containers=true

# Watch a specific pod
kubectl logs -f validator-api-0 -n <namespace>

# Check if package cache is working (should see fewer "Installing" messages on restart)
kubectl logs validator-api-0 -n <namespace> | grep -i "installing"

# Verify package cache is using persistent volume
kubectl exec validator-api-0 -n <namespace> -- ls -lh /home/ktor/.fhir/packages

# Check terminology cache
kubectl exec validator-api-0 -n <namespace> -- ls -lh /tmp/default-tx-cache

# Verify PVCs are bound (should see 4 PVCs total: 2 package + 2 terminology)
kubectl get pvc -n <namespace> | grep validator

# Check StatefulSet status
kubectl get statefulset validator-api -n <namespace>
```

Expected on first deployment (both pods):
- Multiple "Installing hl7.fhir..." messages (packages downloading)
- Terminology cache directory being created
- Both pods download in parallel (~2-3 minutes each)

Expected on pod restarts (per pod):
- No "Installing" messages (packages already cached)
- Fast startup (~10-15 seconds to ready)

Expected PVCs:
```
fhir-package-cache-validator-api-0    5Gi    gp3-encrypted
fhir-package-cache-validator-api-1    5Gi    gp3-encrypted
terminology-cache-validator-api-0     2Gi    gp3-encrypted
terminology-cache-validator-api-1     2Gi    gp3-encrypted
```

## Resource Summary

| Resource | Before | After | Change |
|----------|--------|-------|--------|
| CPU Request | 250m | 1000m | +750m (4x) |
| CPU Limit | 500m | 2000m | +1500m (4x) |
| Memory Request | 3.5Gi | 2.5Gi | -1Gi |
| Memory Limit | 4Gi | 3Gi | -1Gi |
| **Per-pod savings** | - | -1Gi memory | Better CPU utilization |
| **Total savings (2 pods)** | - | -2Gi memory | Eliminates CPU throttling |

## Rollback

If issues occur, you can rollback by:
1. Reverting to the Deployment (use git to restore old deployment file)
2. Deleting StatefulSet: `kubectl delete statefulset validator-api -n <namespace>`
3. Deleting PVCs: `kubectl delete pvc -l app=validator-api -n <namespace>`
4. Reverting resource changes to original values

## Managing PVCs

StatefulSet PVCs persist even after pod deletion. To clean up:
```bash
# Delete all validator PVCs
kubectl delete pvc -n <namespace> \
  fhir-package-cache-validator-api-0 \
  fhir-package-cache-validator-api-1 \
  terminology-cache-validator-api-0 \
  terminology-cache-validator-api-1

# Or delete all at once
kubectl delete pvc -n <namespace> -l app=validator-api
```

Note: Deleting PVCs will force re-download of all packages on next startup.
