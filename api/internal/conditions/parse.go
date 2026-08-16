package conditions

import (
	"strconv"
	"strings"
)

// ParseMph extracts a numeric mph value from an NWS-style wind string such as
// "12 mph" or "10 to 15 mph". Ranges resolve to their maximum. Returns nil for
// empty or unparseable input.
func ParseMph(s string) *float64 {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return nil
	}
	s = strings.TrimSuffix(s, "mph")

	var max *float64
	for _, part := range strings.Split(s, "to") {
		v, err := strconv.ParseFloat(strings.TrimSpace(part), 64)
		if err != nil {
			continue
		}
		if max == nil || v > *max {
			max = &v
		}
	}
	return max
}
