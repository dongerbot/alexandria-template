#!/usr/bin/env bash
# shared helpers (sourced by the other scripts)
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
cfg() { python3 -c "import json,sys;v=json.load(open('config.json')).get(sys.argv[1],'');print(v if v is not None else '')" "$1"; }
cfg_set() { python3 - "$1" "$2" <<'P'
import json,sys;c=json.load(open("config.json"));c[sys.argv[1]]=sys.argv[2];json.dump(c,open("config.json","w"),indent=2,ensure_ascii=False)
P
}
read_key_file() { echo "$HOME/.secrets/alexandria_read_key_$(cfg worker_name)"; }
