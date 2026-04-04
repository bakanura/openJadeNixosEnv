{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    gh
    luarocks
    nh
    powershell
    vscode
  ];
}
