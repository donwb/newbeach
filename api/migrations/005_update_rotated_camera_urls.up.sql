-- The NSB and Ponce Inlet YouTube live broadcasts were replaced with new
-- videos, so their watch URLs rotated. hls_url is left as-is: the stale
-- stream fails on next play, which triggers the refresh path, and the home
-- cron re-resolves from the new youtube_url on its next run.
UPDATE cameras SET youtube_url = 'https://www.youtube.com/watch?v=550p9smwjPM', updated_at = NOW()
    WHERE id = 'nsb';
UPDATE cameras SET youtube_url = 'https://www.youtube.com/watch?v=ZCozdEGwkDI', updated_at = NOW()
    WHERE id = 'ponce-inlet';
