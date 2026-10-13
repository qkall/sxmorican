#!/usr/bin/env python3
# title="$icon_mus Last.FM Scraper"
# sxmo userscript: lastfm-links (wofi version)

import urllib.request
import urllib.parse
import subprocess
import re
import sys
import json
import os
import xml.etree.ElementTree as ET

LOG_FILE = os.path.expanduser("~/lastfm_debug.log")

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{msg}\n")
    except Exception:
        pass

def notify(msg):
    log(f"NOTIFICATION: {msg}")
    subprocess.run(["notify-send", "Last.FM Scraper", msg])

def wofi_menu(options, prompt):
    proc = subprocess.run(
        ["wofi", "--show", "dmenu", "--prompt", prompt],
        input="\n".join(options), text=True, stdout=subprocess.PIPE
    )
    return proc.stdout.strip()

def main():
    log("--- Script Started ---")
    
    # Using the public Last.fm RSS feed endpoint which avoids Cloudflare bot challenges
    rss_url = "https://lfm.xiffy.nl/uleftwithsilenc"
    log(f"Fetching RSS Feed URL: {rss_url}")

    try:
        req = urllib.request.Request(rss_url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        xml_data = urllib.request.urlopen(req, timeout=5).read()
        log(f"Successfully fetched RSS feed. Length: {len(xml_data)} bytes.")
    except Exception as e:
        log(f"ERROR: Failed to reach RSS feed: {e}")
        notify("Failed to reach Last.fm RSS feed.")
        sys.exit(1)

    try:
        root = ET.fromstring(xml_data)
        item = root.find('.//item')
        if item is None:
            raise ValueError("No items found in RSS feed.")
        
        title_elem = item.find('title')
        if title_elem is None or not title_elem.text:
            raise ValueError("No title tag found in RSS item.")
        
        raw_title = title_elem.text.strip()
        log(f"Parsed RSS item title: '{raw_title}'")
        
        # Typically formatted as "Artist - Track" or "Artist – Track"
        match = re.search(r'^(.*?)\s*[-–]\s*(.*)$', raw_title)
        if not match:
            raise ValueError(f"Could not split artist and track from: {raw_title}")
            
        artist = match.group(1).strip()
        title = match.group(2).strip()
        log(f"Successfully parsed track -> Artist: '{artist}', Title: '{title}'")
        
    except Exception as e:
        log(f"ERROR: Failed to parse RSS XML: {e}")
        notify("Could not parse recent track from RSS feed.")
        sys.exit(1)

    query = f"{artist} {title}"
    encoded_q = urllib.parse.quote_plus(query)

    yt_url = f"https://www.youtube.com/results?search_query={encoded_q}"
    lfm_artist = urllib.parse.quote_plus(artist)
    lfm_track = urllib.parse.quote_plus(title)
    lastfm_url = f"https://www.last.fm/music/{lfm_artist}/_/{lfm_track}"
    qobuz_url = f"https://www.qobuz.com/us-en/search?q={encoded_q}"

    try:
        itunes_api = f"https://itunes.apple.com/search?term={encoded_q}&entity=song&limit=1"
        log(f"Querying iTunes API: {itunes_api}")
        req = urllib.request.Request(itunes_api, headers={"User-Agent": "Mozilla/5.0"})
        res = urllib.request.urlopen(req, timeout=3).read().decode("utf-8")
        itunes_data = json.loads(res)
        
        if itunes_data.get("resultCount", 0) > 0:
            itunes_track_url = itunes_data["results"][0]["trackViewUrl"]
            log(f"iTunes track URL found: {itunes_track_url}")
            odesli_api = f"https://api.song.link/v1-alpha.1/links?url={urllib.parse.quote_plus(itunes_track_url)}"
            req2 = urllib.request.Request(odesli_api, headers={"User-Agent": "Mozilla/5.0"})
            res2 = urllib.request.urlopen(req2, timeout=3).read().decode("utf-8")
            odesli_data = json.loads(res2)
            
            links = odesli_data.get("linksByPlatform", {})
            if "qobuz" in links:
                qobuz_url = links["qobuz"]["url"]
                log(f"Found Qobuz link via Odesli: {qobuz_url}")
        else:
            log("iTunes API returned 0 results.")
    except Exception as e:
        log(f"Warning/Error during API resolution: {e}")
        pass

    def shorten(u):
        try:
            api = "https://da.gd/s?url=" + urllib.parse.quote_plus(u)
            req = urllib.request.Request(api, headers={"User-Agent": "curl/7.0"})
            res = urllib.request.urlopen(req, timeout=3).read().decode("utf-8").strip()
            return res if res.startswith("https://da.gd/") else u
        except Exception as e:
            log(f"Failed to shorten URL {u}: {e}")
            return u

    short_yt = shorten(yt_url)
    short_lfm = shorten(lastfm_url)
    short_qobuz = shorten(qobuz_url)

    qobuz_text = f'Check out the track "{title}" by {artist} on Qobuz!: {short_qobuz}'
    yt_text = f'Check out the track "{title}" by {artist} on YouTube: {short_yt}'
    all_text = f'"{title}" by {artist}. Qobuz: {short_qobuz} | YT: {short_yt} | Last.fm: {short_lfm}'

    options = ["Copy Qobuz Link", "Copy YouTube Link", "Copy All Links"]
    action = wofi_menu(options, f"Found: {artist} - {title}")
    log(f"User selected action: '{action}'")

    clipboard_text = ""
    if action == "Copy Qobuz Link":
        clipboard_text = qobuz_text
    elif action == "Copy YouTube Link":
        clipboard_text = yt_text
    elif action == "Copy All Links":
        clipboard_text = all_text

    if clipboard_text:
        try:
            subprocess.run(["wl-copy"], input=clipboard_text, text=True, check=True)
            log("Copied to clipboard using wl-copy.")
        except Exception:
            subprocess.run(["xclip", "-selection", "clipboard"], input=clipboard_text, text=True)
            log("Copied to clipboard using xclip.")
        notify("Copied to clipboard!")

    log("--- Script Finished Successfully ---")

if __name__ == "__main__":
    main()
