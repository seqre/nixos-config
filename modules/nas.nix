# Homelab NAS: the NFS export 192.168.0.100:/export/nas at /mnt/nas.
#
# Not mounted at boot: a systemd automount mounts it on first access and unmounts it after 10 idle minutes, so the
# laptop doesn't keep a mount to a server it may have left behind. Away from home an access fails after the mount
# timeout instead of hanging. /mnt/nas lives on the ephemeral root; systemd creates it on every boot.
#
# Not shown through x-gvfs-show: gvfs ignores the autofs mount, so it would offer the share as an unmounted volume,
# and clicking it runs mount(8) as the user, which fails without the `user` option. A Files bookmark to /mnt/nas
# works: opening it triggers the automount.
{
  # nfs-utils (mount.nfs, showmount, nfsstat), rpcbind and rpc.statd (NFSv3 locking). The NFS fileSystems entry below
  # implies this too; explicit so `mount -t nfs` keeps working for other shares.
  boot.supportedFilesystems.nfs = true;

  fileSystems."/mnt/nas" = {
    # NFSv4 only. The server exports /export as the v4 root (fsid=0), so /export/nas is /nas here; asking for
    # /export/nas fails over v4 and mount.nfs falls back to v3, which needs rpc.statd and lock callbacks through the
    # firewall. The server squashes every user to its `nfs` user (uid/gid 990), so files show as owned by 990.
    device = "192.168.0.100:/nas";
    fsType = "nfs4";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      # mount.nfs would keep retrying an unreachable server for 2 minutes. 15 s leaves room for Wi-Fi to reconnect
      # after resume.
      "x-systemd.mount-timeout=15s"
    ];
  };
}
