{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    alejandra
    onefetch
    atop
    go # needed for waybar-weather compile
    chafa # terminal image to ASCII renderer
    librsvg # provides rsvg-convert for SVG -> raster conversion
  ];
}
