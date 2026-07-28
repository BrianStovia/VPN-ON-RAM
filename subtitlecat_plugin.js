/**
 * SubtitleCat Plugin for Jellyfin Web & Custom Player
 * Standalone plugin integrated with Jellyfin Server API to search, download,
 * auto-attach, and permanently upload subtitles to Jellyfin Server!
 */
(function (global) {
    console.log('[SubtitleCat Plugin] Loaded SubtitleCat Server-API Integrated Plugin');

    const SubtitleCatPlugin = {
        // Convert SRT format to WebVTT
        srtToVtt: function (srtText) {
            let vtt = "WEBVTT\n\n" + srtText
                .replace(/\r\n/g, '\n')
                .replace(/\r/g, '\n')
                .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2')
                .replace(/{[^}]+}/g, '');
            return vtt;
        },

        // Get Current ItemId from Jellyfin Web DOM/URL
        getCurrentItemId: function () {
            const hash = window.location.hash || '';
            const match = hash.match(/id=([a-f0-9]+)/i) || hash.match(/item(?:Id)?\/([a-f0-9]+)/i);
            if (match && match[1]) return match[1];

            const itemElem = document.querySelector('[data-itemid]');
            if (itemElem) return itemElem.dataset.itemid;

            return null;
        },

        // Attach Subtitle to Video Tag for Instant Playback
        attachTrack: function (subContent, label) {
            const video = document.querySelector('video');
            if (!video) return false;

            let vttContent = subContent;
            if (!subContent.trim().startsWith('WEBVTT')) {
                vttContent = this.srtToVtt(subContent);
            }

            // Remove existing custom tracks
            const existingTracks = video.querySelectorAll('track[data-subcat-track="true"]');
            existingTracks.forEach(t => t.remove());

            const blob = new Blob([vttContent], { type: 'text/vtt' });
            const trackUrl = URL.createObjectURL(blob);

            const track = document.createElement('track');
            track.kind = 'subtitles';
            track.label = label || 'SubtitleCat';
            track.srclang = 'id';
            track.src = trackUrl;
            track.default = true;
            track.dataset.subcatTrack = 'true';

            video.appendChild(track);

            setTimeout(() => {
                for (let i = 0; i < video.textTracks.length; i++) {
                    const tt = video.textTracks[i];
                    if (tt.label && tt.label.includes('SubtitleCat')) {
                        tt.mode = 'showing';
                    } else {
                        tt.mode = 'disabled';
                    }
                }
            }, 200);

            return true;
        },

        // Upload Subtitle permanently to Jellyfin Server API
        uploadToServerAPI: async function (subContent, langCode, format) {
            const itemId = this.getCurrentItemId();
            if (!itemId) {
                console.log('[SubtitleCat Plugin] Could not detect current itemId for API upload.');
                return false;
            }

            const api = (typeof ApiClient !== 'undefined') ? ApiClient : (window.ApiClient || null);
            if (!api) {
                console.log('[SubtitleCat Plugin] ApiClient not found, skipping server API upload.');
                return false;
            }

            try {
                // Encode UTF-8 text to base64
                const base64Data = btoa(unescape(encodeURIComponent(subContent)));
                const serverUrl = api.getUrl(`/Items/${itemId}/Subtitles`);

                const headers = {
                    'Content-Type': 'application/json'
                };

                if (api.getAuthorizationHeader) {
                    headers['X-Emby-Authorization'] = api.getAuthorizationHeader();
                }

                const response = await fetch(serverUrl, {
                    method: 'POST',
                    headers: headers,
                    body: JSON.stringify({
                        Language: langCode || 'ind',
                        Format: format || 'srt',
                        IsForced: false,
                        Data: base64Data
                    })
                });

                if (response.ok) {
                    console.log('[SubtitleCat Plugin] Subtitle successfully saved to Jellyfin Server API for ItemId:', itemId);
                    return true;
                }
            } catch (err) {
                console.error('[SubtitleCat Plugin] Failed uploading subtitle to Jellyfin Server API:', err);
            }
            return false;
        },

        // Search SubtitleCat
        search: async function (query) {
            const cleanQuery = query.replace(/\(\d{4}\)/g, '').trim();
            const searchUrl = `https://www.subtitlecat.com/index.php?search=${encodeURIComponent(cleanQuery)}`;

            let htmlText = '';
            try {
                const response = await fetch(searchUrl);
                htmlText = await response.text();
            } catch (err) {
                // Fallback to CORS proxy if cross-origin blocked
                const proxyResp = await fetch(`https://api.allorigins.win/get?url=${encodeURIComponent(searchUrl)}`);
                const data = await proxyResp.json();
                htmlText = data.contents;
            }

            const parser = new DOMParser();
            const doc = parser.parseFromString(htmlText, 'text/html');
            const rows = doc.querySelectorAll('table.sub-table tr, .sub-table tbody tr, table tr');
            const results = [];

            rows.forEach(row => {
                const links = row.querySelectorAll('a');
                if (links.length > 0) {
                    const titleAnchor = links[0];
                    const href = titleAnchor.getAttribute('href');
                    const title = titleAnchor.innerText.trim();
                    const langMatch = row.innerText.match(/Indonesian|English|Malay|Spanish|Japanese/i);
                    const lang = langMatch ? langMatch[0] : 'Indonesian';

                    if (href && title && (href.includes('.html') || href.includes('subtitles'))) {
                        results.push({
                            title: title,
                            lang: lang,
                            url: href.startsWith('http') ? href : `https://www.subtitlecat.com/${href.replace(/^\//, '')}`
                        });
                    }
                }
            });

            return results;
        },

        // Download subtitle file from result URL & process attach + API upload
        downloadAndAttach: async function (itemUrl, itemLang) {
            const parser = new DOMParser();
            let subHtml = '';
            try {
                const resp = await fetch(itemUrl);
                subHtml = await resp.text();
            } catch (e) {
                const proxyResp = await fetch(`https://api.allorigins.win/get?url=${encodeURIComponent(itemUrl)}`);
                const d = await proxyResp.json();
                subHtml = d.contents;
            }

            const subDoc = parser.parseFromString(subHtml, 'text/html');
            const dlLink = subDoc.querySelector('#download_sub, a[href*=".srt"], a[href*=".vtt"], a[download]');
            let fileUrl = dlLink ? dlLink.getAttribute('href') : '';

            if (!fileUrl) throw new Error('Download link not found');

            if (!fileUrl.startsWith('http')) {
                fileUrl = `https://www.subtitlecat.com/${fileUrl.replace(/^\//, '')}`;
            }

            let subText = '';
            try {
                const fileResp = await fetch(fileUrl);
                subText = await fileResp.text();
            } catch (e) {
                const proxyResp = await fetch(`https://api.allorigins.win/get?url=${encodeURIComponent(fileUrl)}`);
                const fd = await proxyResp.json();
                subText = fd.contents;
            }

            // 1. Instantly attach for local video playback
            const attached = this.attachTrack(subText, `SubtitleCat (${itemLang})`);

            // 2. Permanently upload to Jellyfin Server API in background
            const langCode = itemLang.toLowerCase().includes('ind') ? 'ind' : 'eng';
            const format = fileUrl.endsWith('.vtt') ? 'vtt' : 'srt';
            this.uploadToServerAPI(subText, langCode, format);

            return attached;
        }
    };

    global.SubtitleCatPlugin = SubtitleCatPlugin;
})(typeof window !== 'undefined' ? window : this);
