#!/usr/bin/env python3
"""
Switchroot Release Version Bump & Changelog Generator
Follows custom versioning rules:
  - Initial version: 1.0.0
  - Increments Z: 1.0.0 -> 1.0.1 -> ... -> 1.0.10
  - When Z exceeds 10: Z=0, Y+=1 (e.g. 1.0.10 -> 1.1.0)
  - When Y exceeds 10: Y=0, X+=1 (e.g. 1.10.10 -> 2.0.0)
  - Ensures the candidate version does not collide with existing tags.
  - Generates comprehensive release notes listing all commits.
"""

import sys
import re
import subprocess
import os

def run_git(cmd):
    try:
        res = subprocess.check_output(['git'] + cmd, stderr=subprocess.DEVNULL)
        return res.decode('utf-8').strip()
    except Exception:
        return ""

def get_all_tags():
    # Attempt to fetch all remote tags
    run_git(['fetch', '--tags', 'origin'])
    
    # 1. Local tags
    out = run_git(['tag', '-l'])
    raw_tags = set(out.splitlines()) if out else set()
    
    # 2. Remote tags via ls-remote as robust fallback
    ls_out = run_git(['ls-remote', '--tags', 'origin'])
    if ls_out:
        for line in ls_out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1].startswith('refs/tags/'):
                tag_name = parts[1].replace('refs/tags/', '').replace('^{}', '')
                if tag_name:
                    raw_tags.add(tag_name)
                    
    tags = []
    seen = set()
    for line in raw_tags:
        tag = line.strip().lstrip('v')
        m = re.match(r'^(\d+)\.(\d+)\.(\d+)$', tag)
        if m:
            entry = (int(m.group(1)), int(m.group(2)), int(m.group(3)), line.strip())
            tup = (entry[0], entry[1], entry[2])
            if tup not in seen:
                seen.add(tup)
                tags.append(entry)
    return tags

def next_version(x, y, z):
    z += 1
    if z > 10:
        z = 0
        y += 1
        if y > 10:
            y = 0
            x += 1
    return x, y, z

def calculate_new_version(tags):
    if not tags:
        return 1, 0, 0, None
    
    # Sort tags by (x, y, z)
    sorted_tags = sorted(tags, key=lambda t: (t[0], t[1], t[2]))
    latest_x, latest_y, latest_z, latest_raw = sorted_tags[-1]
    
    existing_tuples = {(t[0], t[1], t[2]) for t in tags}
    
    # Bump until we find an unused version
    cur_x, cur_y, cur_z = latest_x, latest_y, latest_z
    while True:
        cur_x, cur_y, cur_z = next_version(cur_x, cur_y, cur_z)
        if (cur_x, cur_y, cur_z) not in existing_tuples:
            break
            
    return cur_x, cur_y, cur_z, latest_raw

def generate_changelog(prev_tag, new_version_str):
    if prev_tag:
        git_range = f"{prev_tag}..HEAD"
        cmd = ['log', git_range, '--pretty=format:- %s (`%h` by %an)']
    else:
        cmd = ['log', '--pretty=format:- %s (`%h` by %an)']
        
    log_output = run_git(cmd)
    if not log_output.strip():
        log_output = "- General updates and performance improvements."
        
    desktop_env = os.environ.get("DESKTOP_ENV", "xfce4")
    changelog = f"""## Switchroot Debian 13 (Trixie) [{desktop_env.upper()}] - Release v{new_version_str}

### Changes in this Release:
{log_output}

### Installation Instructions:
1. Download `switch-debian-13-trixie-{desktop_env}-installer-hekate.zip`.
2. Extract the archive directly onto the root of your MicroSD card (FAT32 partition).
3. Insert the MicroSD into your Nintendo Switch and enter Hekate Nyx.
4. Navigate to **Tools -> Partition SD Card -> Flash Linux**.
5. Wait for the flash to complete, then tap **Reboot -> More Configs -> Debian 13 (Trixie)**.
6. The filesystem will automatically resize to fill 100% of your ext4 partition on first boot.
"""
    return changelog

def main():
    tags = get_all_tags()
    x, y, z, prev_tag = calculate_new_version(tags)
    ver_str = f"{x}.{y}.{z}"
    tag_str = f"v{ver_str}"
    
    changelog = generate_changelog(prev_tag, ver_str)
    
    # Write changelog to file
    out_file = sys.argv[1] if len(sys.argv) > 1 else "RELEASE_NOTES.md"
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(changelog)
        
    # Output for GitHub Actions if GITHUB_OUTPUT is set
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as gh:
            gh.write(f"version={ver_str}\n")
            gh.write(f"tag={tag_str}\n")
            gh.write(f"prev_tag={prev_tag if prev_tag else ''}\n")
            gh.write(f"changelog_file={out_file}\n")
            
    print(f"BUMP: {prev_tag} -> {tag_str}")
    print(f"Changelog written to {out_file}")

if __name__ == "__main__":
    main()
