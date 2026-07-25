#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-root@192.168.0.104}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${REPO_ROOT}/backups/photos-db-${STAMP}"
PHOTO_DIR="/var/mobile/Media/PhotoData"
SQLITE="/usr/bin/sqlite3"

if [[ ! -x "${SQLITE}" ]]; then
  echo "missing ${SQLITE}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}/raw" "${BACKUP_DIR}/work" "${BACKUP_DIR}/post-apply-verify"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
scp_opts=(-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "backup_dir=${BACKUP_DIR}"
echo "device=${DEVICE}"

copy_from_phone() {
  local target_dir="$1"
  scp "${scp_opts[@]}" "${DEVICE}:${PHOTO_DIR}/Photos.sqlite" "${target_dir}/Photos.sqlite"
  scp "${scp_opts[@]}" "${DEVICE}:${PHOTO_DIR}/Photos.sqlite-wal" "${target_dir}/Photos.sqlite-wal"
  scp "${scp_opts[@]}" "${DEVICE}:${PHOTO_DIR}/Photos.sqlite-shm" "${target_dir}/Photos.sqlite-shm"
}

verify_db() {
  local db="$1"
  "${SQLITE}" -header -column "${db}" "
    PRAGMA integrity_check;
    WITH visible AS (
      SELECT *
      FROM ZASSET
      WHERE ZDATECREATED IS NOT NULL
        AND ZADDEDDATE IS NOT NULL
        AND COALESCE(ZTRASHEDSTATE, 0) = 0
        AND COALESCE(ZHIDDEN, 0) = 0
    ),
    ranked AS (
      SELECT
        Z_PK,
        ROW_NUMBER() OVER (ORDER BY ZADDEDDATE ASC, Z_PK ASC) AS added_rank,
        ROW_NUMBER() OVER (ORDER BY ZDATECREATED ASC, Z_PK ASC) AS created_rank
      FROM visible
    )
    SELECT
      COUNT(*) AS visible_count,
      SUM(added_rank != created_rank) AS rank_diff_count,
      MAX(ABS(added_rank - created_rank)) AS max_rank_delta
    FROM ranked;
    SELECT
      Z_PK,
      ZFILENAME,
      datetime(ZDATECREATED + 978307200, 'unixepoch') AS created,
      datetime(ZADDEDDATE + 978307200, 'unixepoch') AS added
    FROM ZASSET
    ORDER BY ZADDEDDATE DESC, Z_PK DESC
    LIMIT 12;
  "
}

echo "copying raw database trio..."
copy_from_phone "${BACKUP_DIR}/raw"

cp "${BACKUP_DIR}/raw/Photos.sqlite" "${BACKUP_DIR}/work/Photos.sqlite"
cp "${BACKUP_DIR}/raw/Photos.sqlite-wal" "${BACKUP_DIR}/work/Photos.sqlite-wal"
cp "${BACKUP_DIR}/raw/Photos.sqlite-shm" "${BACKUP_DIR}/work/Photos.sqlite-shm"

tar -czf "${BACKUP_DIR}/raw-photos-sqlite-trio.tar.gz" -C "${BACKUP_DIR}/raw" Photos.sqlite Photos.sqlite-wal Photos.sqlite-shm

"${SQLITE}" -header -csv "${BACKUP_DIR}/work/Photos.sqlite" \
  "SELECT Z_PK,ZUUID,ZFILENAME,ZDATECREATED,ZADDEDDATE,ZSORTTOKEN,ZTRASHEDSTATE,ZHIDDEN FROM ZASSET ORDER BY Z_PK;" \
  > "${BACKUP_DIR}/asset_sort_fields_before.csv"

cat > "${BACKUP_DIR}/work/reorder_updates.sql" <<'SQL'
PRAGMA trusted_schema=ON;
BEGIN IMMEDIATE;

CREATE TABLE IF NOT EXISTS AYAOPHOTO_REORDER_BACKUP AS
SELECT Z_PK,ZUUID,ZFILENAME,ZDATECREATED,ZADDEDDATE,ZSORTTOKEN,ZTRASHEDSTATE,ZHIDDEN
FROM ZASSET;

WITH ranked AS (
  SELECT
    Z_PK,
    ZDATECREATED + ((ROW_NUMBER() OVER (PARTITION BY ZDATECREATED ORDER BY Z_PK ASC) - 1) * 0.001) AS new_added
  FROM ZASSET
  WHERE ZDATECREATED IS NOT NULL
    AND ZADDEDDATE IS NOT NULL
)
UPDATE ZASSET
SET ZADDEDDATE = (SELECT new_added FROM ranked WHERE ranked.Z_PK = ZASSET.Z_PK)
WHERE Z_PK IN (SELECT Z_PK FROM ranked);

COMMIT;
PRAGMA wal_checkpoint(TRUNCATE);
SQL

echo "applying reorder to local work copy..."
"${SQLITE}" "${BACKUP_DIR}/work/Photos.sqlite" < "${BACKUP_DIR}/work/reorder_updates.sql"

echo "local verification:"
verify_db "${BACKUP_DIR}/work/Photos.sqlite" | tee "${BACKUP_DIR}/verify-local.txt"

rank_diff="$("${SQLITE}" "${BACKUP_DIR}/work/Photos.sqlite" "
  WITH visible AS (
    SELECT *
    FROM ZASSET
    WHERE ZDATECREATED IS NOT NULL
      AND ZADDEDDATE IS NOT NULL
      AND COALESCE(ZTRASHEDSTATE, 0) = 0
      AND COALESCE(ZHIDDEN, 0) = 0
  ),
  ranked AS (
    SELECT
      ROW_NUMBER() OVER (ORDER BY ZADDEDDATE ASC, Z_PK ASC) AS added_rank,
      ROW_NUMBER() OVER (ORDER BY ZDATECREATED ASC, Z_PK ASC) AS created_rank
    FROM visible
  )
  SELECT COALESCE(SUM(added_rank != created_rank), 0) FROM ranked;
")"

if [[ "${rank_diff}" != "0" ]]; then
  echo "local rank verification failed: rank_diff=${rank_diff}" >&2
  exit 1
fi

echo "stopping photo services..."
ssh "${ssh_opts[@]}" "${DEVICE}" "
  killall MobileSlideShow 2>/dev/null || true
  killall PhotosFileProvider 2>/dev/null || true
  killall photolibraryd 2>/dev/null || true
  killall assetsd 2>/dev/null || true
  killall cloudphotod 2>/dev/null || true
  sleep 2
"

echo "copying reordered database trio back to phone..."
scp "${scp_opts[@]}" "${BACKUP_DIR}/work/Photos.sqlite" "${DEVICE}:${PHOTO_DIR}/Photos.sqlite"
scp "${scp_opts[@]}" "${BACKUP_DIR}/work/Photos.sqlite-wal" "${DEVICE}:${PHOTO_DIR}/Photos.sqlite-wal"
scp "${scp_opts[@]}" "${BACKUP_DIR}/work/Photos.sqlite-shm" "${DEVICE}:${PHOTO_DIR}/Photos.sqlite-shm"

ssh "${ssh_opts[@]}" "${DEVICE}" "
  chown mobile:mobile ${PHOTO_DIR}/Photos.sqlite ${PHOTO_DIR}/Photos.sqlite-wal ${PHOTO_DIR}/Photos.sqlite-shm
  chmod 0644 ${PHOTO_DIR}/Photos.sqlite ${PHOTO_DIR}/Photos.sqlite-wal ${PHOTO_DIR}/Photos.sqlite-shm
  killall MobileSlideShow 2>/dev/null || true
  killall PhotosFileProvider 2>/dev/null || true
  killall photolibraryd 2>/dev/null || true
  killall assetsd 2>/dev/null || true
  killall cloudphotod 2>/dev/null || true
"

echo "copying phone database back for post-apply verification..."
copy_from_phone "${BACKUP_DIR}/post-apply-verify"

echo "post-apply verification:"
verify_db "${BACKUP_DIR}/post-apply-verify/Photos.sqlite" | tee "${BACKUP_DIR}/verify-post-apply.txt"

echo "done"
du -sh "${BACKUP_DIR}" "${BACKUP_DIR}/raw-photos-sqlite-trio.tar.gz"
