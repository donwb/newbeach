package predict

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDaypartBoundaries(t *testing.T) {
	assert.Equal(t, daypartMorning, daypartOf(et(1, 6, 0)))
	assert.Equal(t, daypartMorning, daypartOf(et(1, 10, 59)))
	assert.Equal(t, daypartMidday, daypartOf(et(1, 11, 0)))
	assert.Equal(t, daypartMidday, daypartOf(et(1, 15, 59)))
	assert.Equal(t, daypartEvening, daypartOf(et(1, 16, 0)))
	assert.Equal(t, daypartEvening, daypartOf(et(1, 23, 0)))
}

// The phrase holds for a whole daypart on every device, and changes at most
// three times a day — never between 10-minute refreshes.
func TestPickVariantStableWithinDaypart(t *testing.T) {
	pool := surfPools[SurfFlat]
	a := pickVariant(et(1, 8, 0), "surf", pool)
	for m := 0; m < 11*60; m += 10 {
		assert.Equal(t, a, pickVariant(et(1, 0, 0).Add(time.Duration(m)*time.Minute), "surf", pool))
	}
	assert.Contains(t, pool, a)
	// Different salt, same moment → independent pick (not necessarily
	// different, but must still be a pool member).
	assert.Contains(t, pool, pickVariant(et(1, 8, 0), "verdict", pool))
}

// Across a month of dayparts every phrase in every pool gets used — the
// seed actually spreads, rather than pinning one index.
func TestPickVariantSpreads(t *testing.T) {
	for key, pool := range surfPools {
		seen := map[string]bool{}
		for day := 1; day <= 30; day++ {
			for _, h := range []int{8, 13, 18} {
				seen[pickVariant(et(day, h, 0), "surf", pool)] = true
			}
		}
		assert.Len(t, seen, len(pool), key)
	}
}

// Every variant fits where the original fit: the tvOS surf headline is one
// 42pt line, the verdict a single 84pt line. Budgets are the longest
// original strings with the longest label ("overhead") substituted.
func TestVoicePoolsFitTheirSlots(t *testing.T) {
	for key, pool := range surfPools {
		require.NotEmpty(t, pool, key)
		for _, v := range pool {
			line := fillHeight(v, "overhead")
			assert.LessOrEqual(t, len([]rune(line)), 52, "%s: %q", key, line)
			if strings.HasSuffix(key, ":nolabel") {
				assert.NotContains(t, v, "{h}")
			} else if key != SurfFlat && key != SurfBlown {
				assert.True(t, strings.Contains(v, "{h}") || strings.Contains(v, "{H}"),
					"%s: %q should carry the height read", key, v)
			}
		}
	}
	for _, v := range allOpenHeadlines {
		line := strings.ReplaceAll(strings.ReplaceAll(v, "{n}", "twelve"), "{N}", "Twelve")
		assert.LessOrEqual(t, len([]rune(line)), 28, line)
	}
	for _, v := range noTideTroubleLeads {
		assert.LessOrEqual(t, len([]rune(v)), 40, v)
	}
}

func TestAllOpenHeadline(t *testing.T) {
	assert.Equal(t, "The ramp is open", allOpenHeadline(et(1, 9, 0), 1))
	got := allOpenHeadline(et(1, 9, 0), 5)
	assert.NotContains(t, got, "{")
	assert.Contains(t, allOpenVariants(5), got)
}

// surfPhrase never leaks a placeholder and always quotes the height when
// the read has one.
func TestSurfPhraseFillsHeight(t *testing.T) {
	for _, q := range []string{SurfChoppy, SurfCleanSmall, SurfGood, SurfFiring} {
		for day := 1; day <= 10; day++ {
			line := surfPhrase(et(day, 9, 0), q, "waist-high")
			assert.NotContains(t, line, "{")
			assert.Contains(t, line, "aist-high", q)
		}
	}
	for _, q := range []string{SurfChoppy, SurfCleanSmall} {
		line := surfPhrase(et(1, 9, 0), q, "")
		assert.NotContains(t, line, "{")
		assert.NotEmpty(t, line)
	}
}
