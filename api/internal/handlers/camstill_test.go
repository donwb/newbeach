package handlers

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCamStillURL(t *testing.T) {
	const want = "https://i.ytimg.com/vi/550p9smwjPM/maxresdefault_live.jpg"
	tests := []struct {
		name string
		url  string
		tmpl string
		want string
	}{
		{"watch url", "https://www.youtube.com/watch?v=550p9smwjPM", "", want},
		{"watch url extra params", "https://www.youtube.com/watch?v=550p9smwjPM&t=10s", "", want},
		{"leading dash id", "https://www.youtube.com/watch?v=-grSyQa817o", "",
			"https://i.ytimg.com/vi/-grSyQa817o/maxresdefault_live.jpg"},
		{"mobile host", "https://m.youtube.com/watch?v=550p9smwjPM", "", want},
		{"short link", "https://youtu.be/550p9smwjPM", "", want},
		{"live path", "https://www.youtube.com/live/550p9smwjPM", "", want},
		{"embed path", "https://www.youtube.com/embed/550p9smwjPM", "", want},
		{"custom template", "https://youtu.be/550p9smwjPM", "https://img.example/{id}.jpg",
			"https://img.example/550p9smwjPM.jpg"},
		{"disabled", "https://youtu.be/550p9smwjPM", "off", ""},
		{"empty url", "", "", ""},
		{"channel url", "https://www.youtube.com/@VolusiaBeaches/live", "", ""},
		{"wrong length id", "https://www.youtube.com/watch?v=abc", "", ""},
		{"not youtube", "https://cams.donwb.com/nsb/index.m3u8", "", ""},
		{"id with bad chars", "https://www.youtube.com/watch?v=550p9smwj%2FM", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, camStillURL(tt.url, tt.tmpl))
		})
	}
}
