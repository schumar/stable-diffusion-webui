import json
import os
from operator import itemgetter

from modules import shared, ui_extra_networks
from modules.hypernetworks import hypernetwork


class ExtraNetworksPageHypernetworks(ui_extra_networks.ExtraNetworksPage):
    def __init__(self):
        super().__init__('Hypernetworks')

    def refresh(self):
        shared.reload_hypernetworks()

    def list_items(self):
        hypernetwork: hypernetwork.HypernetworkInfo
        for title, hypernetwork in sorted(shared.hypernetworks_full.items(), key=itemgetter(0)):
            path, ext = os.path.splitext(hypernetwork.filename)

            name = hypernetwork.name_for_extra
            displayname = name
            if hypernetwork.meta:
                if hypernetwork.meta.get('displayname'):
                    displayname = "✅ " + hypernetwork.meta['displayname']
                elif hypernetwork.meta.get('title'):
                    displayname = "🗸 " + hypernetwork.meta['title']

            yield {
                "name": displayname,
                "filename": hypernetwork.filename,
                "preview": self.find_preview(path),
                "description": self.find_description(path),
                "search_term": self.search_terms_from_path(path),
                "prompt": json.dumps(f"<hypernet:{name}:") + " + opts.extra_networks_default_multiplier + " + json.dumps(">"),
                "local_preview": f"{path}.preview.{shared.opts.samples_format}",
            }

    def allowed_directories_for_previews(self):
        return [shared.cmd_opts.hypernetwork_dir]

