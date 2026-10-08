"""Finder layout for the German drag-to-install disk image (dmgbuild settings)."""
from pathlib import Path

application = Path(defines["app"]).resolve()
format = "UDZO"
filesystem = "HFS+"
files = [str(application)]
symlinks = {"Programme": "/Applications"}
icon = str(application / "Contents/Resources/Inlaut.icns")
background = defines["background"]  # dmgbuild also picks up the @2x PNG.
# Do not set FinderInfo on the signed app, even to hide its extension: codesign
# rejects that extra metadata. Finder normally hides application extensions.
hide_extensions = []
icon_locations = {application.name: (176, 252), "Programme": (484, 252)}
window_rect = ((200, 180), (660, 462))  # 430 pt artwork + Finder's title bar.
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 54  # Finder rejects saved icon-view settings with spacing >= 100.
icon_size = 104
text_size = 14
label_pos = "bottom"
