# Snapper snapshots of the persistent subvolumes. The root is recreated every boot (impermanence) and the system is
# covered by NixOS generations, so only /home and /persist hold state worth snapshotting. Each has a `.snapshots`
# subvolume (snapper's layout), created at install time. Retention is the same as Ubuntu's snapper config for `@`:
# 5 hourly, 7 daily, 2 weekly, 1 monthly. Snapshots are not backups: they live on the same disk.
#
#   snapper -c home list                      # as seqre (ALLOW_USERS)
#   sudo snapper -c persist list
#   snapper -c home create -d "before X"      # manual snapshot
#   files: /home/.snapshots/<N>/snapshot/..., /persist/.snapshots/<N>/snapshot/...
#
# Future: consider btrbk instead of (or next to) snapper: same local snapshots, plus incremental `btrfs send` to
# another disk or machine, which would make these actual backups.
{ ... }:

let
  retention = {
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_MIN_AGE = 1800;
    TIMELINE_LIMIT_HOURLY = 5;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 2;
    TIMELINE_LIMIT_MONTHLY = 1;
    TIMELINE_LIMIT_YEARLY = 0;
    NUMBER_CLEANUP = true;
    NUMBER_MIN_AGE = 1800;
    NUMBER_LIMIT = 20;
    NUMBER_LIMIT_IMPORTANT = 10;
  };
in
{
  services.snapper = {
    persistentTimer = true; # catch up on the hourly snapshot after the laptop was off
    configs = {
      home = retention // {
        SUBVOLUME = "/home";
        ALLOW_USERS = [ "seqre" ];
        SYNC_ACL = true;
      };
      persist = retention // {
        SUBVOLUME = "/persist";
      };
    };
  };
}
