import json
import os
from operator import itemgetter
import lora

from modules import shared, ui_extra_networks


class ExtraNetworksPageLora(ui_extra_networks.ExtraNetworksPage):
    def __init__(self):
        super().__init__('Lora')

    def refresh(self):
        lora.list_available_loras()

    def list_items(self):
        for name, lora_on_disk in sorted(lora.available_loras.items(), key=itemgetter(0)):
            path, ext = os.path.splitext(lora_on_disk.filename)
            displayname = name
            if lora_on_disk.meta:
                if lora_on_disk.meta.get('displayname'):
                    displayname = lora_on_disk.meta['displayname']
                elif lora_on_disk.meta.get('title'):
                    displayname = lora_on_disk.meta['title']

            yield {
                "name": displayname,
                "filename": path,
                "preview": self.find_preview(path),
                "description": self.find_description(path),
                "search_term": self.search_terms_from_path(lora_on_disk.filename),
                "prompt": json.dumps(f"<lora:{name}:") + " + opts.extra_networks_default_multiplier + " + json.dumps(">"),
                "local_preview": f"{path}.{shared.opts.samples_format}",
                "metadata": json.dumps(lora_on_disk.metadata, indent=4) if lora_on_disk.metadata else None,
            }

    def allowed_directories_for_previews(self):
        return [shared.cmd_opts.lora_dir]

