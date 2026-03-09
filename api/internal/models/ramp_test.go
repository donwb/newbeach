package models

import "testing"

func TestStatusToCategory(t *testing.T) {
	tests := []struct {
		name   string
		status string
		want   string
	}{
		{name: "OPEN", status: "OPEN", want: "open"},
		{name: "open lowercase", status: "open", want: "open"},
		{name: "OPEN with spaces", status: "  OPEN  ", want: "open"},
		{name: "4X4 ONLY", status: "4X4 ONLY", want: "limited"},
		{name: "CLOSING IN PROGRESS", status: "CLOSING IN PROGRESS", want: "limited"},
		{name: "OPEN - ENTRANCE ONLY", status: "OPEN - ENTRANCE ONLY", want: "limited"},
		{name: "CLOSED", status: "CLOSED", want: "closed"},
		{name: "CLOSED FOR HIGH TIDE", status: "CLOSED FOR HIGH TIDE", want: "closed"},
		{name: "CLOSED - AT CAPACITY", status: "CLOSED - AT CAPACITY", want: "closed"},
		{name: "CLOSED - CLEARED FOR TURTLES", status: "CLOSED - CLEARED FOR TURTLES", want: "closed"},
		{name: "unknown status", status: "SOMETHING ELSE", want: "closed"},
		{name: "empty string", status: "", want: "closed"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := StatusToCategory(tt.status)
			if got != tt.want {
				t.Errorf("StatusToCategory(%q) = %q, want %q", tt.status, got, tt.want)
			}
		})
	}
}

func TestStatusToShort(t *testing.T) {
	tests := []struct {
		name   string
		status string
		want   string
	}{
		{name: "OPEN", status: "OPEN", want: "OPEN"},
		{name: "CLOSED", status: "CLOSED", want: "CLOSED"},
		{name: "4X4 ONLY", status: "4X4 ONLY", want: "4X4 ONLY"},
		{name: "CLOSED FOR HIGH TIDE", status: "CLOSED FOR HIGH TIDE", want: "CLOSED-TIDE"},
		{name: "CLOSED - AT CAPACITY", status: "CLOSED - AT CAPACITY", want: "CLOSED-FULL"},
		{name: "CLOSED - CLEARED FOR TURTLES", status: "CLOSED - CLEARED FOR TURTLES", want: "CLOSED-TRTL"},
		{name: "CLOSING IN PROGRESS", status: "CLOSING IN PROGRESS", want: "CLOSING"},
		{name: "OPEN - ENTRANCE ONLY", status: "OPEN - ENTRANCE ONLY", want: "ENTER ONLY"},
		{name: "lowercase input", status: "closed for high tide", want: "CLOSED-TIDE"},
		{name: "short abbreviation length", status: "OPEN", want: "OPEN"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := StatusToShort(tt.status)
			if got != tt.want {
				t.Errorf("StatusToShort(%q) = %q, want %q", tt.status, got, tt.want)
			}
			if len(got) > 12 {
				t.Errorf("StatusToShort(%q) = %q (len %d), exceeds 12 char limit", tt.status, got, len(got))
			}
		})
	}
}
