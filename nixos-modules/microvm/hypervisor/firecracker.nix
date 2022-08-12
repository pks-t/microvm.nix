{ config, pkgs, lib, ... }:
let
  inherit (config.microvm) vcpu mem user interfaces volumes shares socket devices;
  rootDisk = config.system.build.squashfs;
in {
  microvm.runner.firecracker = import ../../../pkgs/runner.nix {
    hypervisor = "firecracker";

    inherit config pkgs;

    command =
      if user != null
      then throw "firecracker will not change user"
      else lib.escapeShellArgs (
        [
          "${pkgs.firectl}/bin/firectl"
          "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
          "-m" (toString mem)
          "-c" (toString vcpu)
          "--kernel=${config.system.build.kernel.dev}/vmlinux"
          "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ${toString config.microvm.kernelParams}"
          "--root-drive=${rootDisk}:ro"
        ]
        ++
        lib.optionals (socket != null) [ "-s" socket ]
        ++
        map ({ image, ... }:
          "--add-drive=${image}:rw"
        ) volumes
        ++
        map (_:
          throw "9p/virtiofs shares not implemented for Firecracker"
        ) shares
        ++
        map ({ type, id, mac, ... }:
          if type == "tap"
          then "--tap-device=${id}/${mac}"
          else throw "Unsupported interface type ${type} for Firecracker"
        ) interfaces
        ++
        map (_:
          throw "devices passthrough is not implemented for Firecracker"
        ) devices
      );

    canShutdown = socket != null;

    shutdownCommand =
      if socket != null
      then ''
        api() {
          ${pkgs.curl}/bin/curl \
            --unix-socket ${socket} \
            -H "Accept: application/json" \
            $@
        }

        api -X PUT http://localhost/actions \
          -H "Content-Type: application/json" \
          -d '${builtins.toJSON {
            action_type = "SendCtrlAltDel";
          }}'

        # wait for exit
        ${pkgs.socat}/bin/socat STDOUT UNIX:${socket},shut-none
      ''
      else throw "Cannot shutdown without socket";
  };
}
