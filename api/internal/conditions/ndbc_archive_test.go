package conditions

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// archiveFixture mirrors NDBC's monthly stdmet archive format: oldest-first,
// with the 99.00-style missing sentinels the archives use instead of MM.
const archiveFixture = `#YY  MM DD hh mm WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP  VIS  TIDE
#yr  mo dy hr mn degT m/s  m/s     m   sec   sec degT   hPa  degC  degC  degC  nmi    ft
2026 03 01 00 26 999 99.0 99.0  1.10  9.09  6.05 100 9999.0 999.0  20.9 999.0 99.0 99.00
2026 03 01 00 56 999 99.0 99.0 99.00 99.00 99.00 999 9999.0 999.0  20.9 999.0 99.0 99.00
2026 03 01 01 26 999 99.0 99.0  1.20  8.33  6.11  98 9999.0 999.0  20.9 999.0 99.0 99.00
`

// hourlyFixture mirrors the legacy archive layout: hourly rows, no minutes
// column, year column named YYYY.
const hourlyFixture = `#YYYY MM DD hh WDIR WSPD GST  WVHT   DPD   APD MWD   PRES  ATMP  WTMP  DEWP  VIS  TIDE
#yr   mo dy hr degT m/s  m/s     m   sec   sec degT   hPa  degC  degC  degC  nmi    ft
2007 04 01 00 999 99.0 99.0  0.90  7.14  5.55 110 9999.0 999.0  21.3 999.0 99.0 99.00
`

func TestParseNDBCTable(t *testing.T) {
	t.Run("archive with sentinels", func(t *testing.T) {
		samples, err := parseNDBCTable(bufio.NewScanner(strings.NewReader(archiveFixture)))
		require.NoError(t, err)
		require.Len(t, samples, 2) // the 99.00 WVHT row drops out

		assert.InDelta(t, 1.10*3.28084, samples[0].HeightFt, 0.001)
		require.NotNil(t, samples[0].DominantPeriodS)
		assert.InDelta(t, 9.09, *samples[0].DominantPeriodS, 0.001)
		assert.Equal(t, time.Date(2026, 3, 1, 0, 26, 0, 0, time.UTC), samples[0].Time)
		assert.Equal(t, time.Date(2026, 3, 1, 1, 26, 0, 0, time.UTC), samples[1].Time)
	})

	t.Run("legacy hourly rows without minutes", func(t *testing.T) {
		samples, err := parseNDBCTable(bufio.NewScanner(strings.NewReader(hourlyFixture)))
		require.NoError(t, err)
		require.Len(t, samples, 1)
		assert.Equal(t, time.Date(2007, 4, 1, 0, 0, 0, 0, time.UTC), samples[0].Time)
	})

	t.Run("realtime fixture yields all wave rows", func(t *testing.T) {
		samples, err := parseNDBCTable(bufio.NewScanner(strings.NewReader(ndbcFixture)))
		require.NoError(t, err)
		require.Len(t, samples, 2)
		// Newest-first file order is preserved.
		assert.True(t, samples[0].Time.After(samples[1].Time))
	})
}

func gzipBytes(t *testing.T, s string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	_, err := gz.Write([]byte(s))
	require.NoError(t, err)
	require.NoError(t, gz.Close())
	return buf.Bytes()
}

func TestFetchArchiveMonth(t *testing.T) {
	newClient := func(srv *httptest.Server) *NDBCClient {
		c := NewNDBCClient("41113")
		c.stdmetURL = srv.URL + "/data/stdmet"
		c.historicalURL = srv.URL + "/data/historical/stdmet"
		return c
	}

	t.Run("gzip month file", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/data/stdmet/Mar/4111332026.txt.gz" {
				w.Write(gzipBytes(t, archiveFixture))
				return
			}
			http.NotFound(w, r)
		}))
		defer srv.Close()

		samples, found, err := newClient(srv).FetchArchiveMonth(context.Background(), 2026, time.March)
		require.NoError(t, err)
		assert.True(t, found)
		assert.Len(t, samples, 2)
	})

	t.Run("falls back to plain month file", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/data/stdmet/Mar/41113.txt" {
				w.Write([]byte(archiveFixture))
				return
			}
			http.NotFound(w, r)
		}))
		defer srv.Close()

		samples, found, err := newClient(srv).FetchArchiveMonth(context.Background(), 2026, time.March)
		require.NoError(t, err)
		assert.True(t, found)
		assert.Len(t, samples, 2)
	})

	t.Run("falls back to year archive and filters to the month", func(t *testing.T) {
		yearFixture := archiveFixture +
			"2026 04 01 00 26 999 99.0 99.0  1.30  8.00  6.00 100 9999.0 999.0  21.0 999.0 99.0 99.00\n"
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/data/historical/stdmet/41113h2026.txt.gz" {
				w.Write(gzipBytes(t, yearFixture))
				return
			}
			http.NotFound(w, r)
		}))
		defer srv.Close()

		samples, found, err := newClient(srv).FetchArchiveMonth(context.Background(), 2026, time.March)
		require.NoError(t, err)
		assert.True(t, found)
		assert.Len(t, samples, 2) // April row filtered out
	})

	t.Run("plain month file for a different month keeps falling back", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// The Mar directory serves July's data under the plain name —
			// nothing matches March, so the fetch reports not-found.
			if r.URL.Path == "/data/stdmet/Mar/41113.txt" {
				w.Write([]byte(strings.ReplaceAll(archiveFixture, "2026 03", "2026 07")))
				return
			}
			http.NotFound(w, r)
		}))
		defer srv.Close()

		_, found, err := newClient(srv).FetchArchiveMonth(context.Background(), 2026, time.March)
		require.NoError(t, err)
		assert.False(t, found)
	})

	t.Run("all candidates missing", func(t *testing.T) {
		srv := httptest.NewServer(http.NotFoundHandler())
		defer srv.Close()

		_, found, err := newClient(srv).FetchArchiveMonth(context.Background(), 2026, time.March)
		require.NoError(t, err)
		assert.False(t, found)
	})
}
