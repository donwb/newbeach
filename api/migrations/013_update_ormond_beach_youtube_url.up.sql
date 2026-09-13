-- The Ormond Beach YouTube live broadcast was replaced (the old video went
-- private on 2026-08-16), so its watch URL rotated. Same pattern as 005:
-- the restreamer re-resolves from the new youtube_url at its next roster
-- refresh or kickstart.
UPDATE cameras SET youtube_url = 'https://www.youtube.com/watch?v=p1s7EdZgGvU', updated_at = NOW()
    WHERE id = 'ormond-beach';
