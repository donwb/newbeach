// Package widgetpush tells WidgetKit to reload the Home Screen widgets the
// moment a ramp's status changes (iOS 26 widget push updates). The widget
// extension registers its push token with the API; the ingester calls
// Notify on every status flip; the notifier sends one "content-changed"
// push per registered token through APNs, coalesced and rate-limited so a
// flapping ramp cannot burn the day's budget.
package widgetpush

import (
	"bytes"
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	productionHost = "https://api.push.apple.com"
	sandboxHost    = "https://api.sandbox.push.apple.com"

	// jwtLifetime is how long one provider token is reused. Apple accepts a
	// token for up to an hour and asks for at least twenty minutes between
	// refreshes.
	jwtLifetime = 50 * time.Minute
)

// ErrBadToken marks a device token APNs will never accept again (410
// Unregistered, or 400 BadDeviceToken / DeviceTokenNotForTopic); the
// caller should forget it.
var ErrBadToken = errors.New("device token rejected")

// Sender is what the notifier needs from APNs; Client is the real one.
type Sender interface {
	Send(ctx context.Context, deviceToken, environment string, payload []byte) error
}

// Client is a token-authenticated (JWT / .p8) APNs HTTP/2 client that sends
// widget pushes for one app.
type Client struct {
	teamID   string
	keyID    string
	key      *ecdsa.PrivateKey
	bundleID string
	http     *http.Client

	// hosts lets tests point at an httptest server.
	hosts map[string]string

	mu       sync.Mutex
	jwt      string
	jwtUntil time.Time
	now      func() time.Time
}

// NewClient parses the .p8 key (PEM; literal "\n" sequences from an env var
// are tolerated) and returns a client for bundleID's widgets.
func NewClient(teamID, keyID, p8PEM, bundleID string) (*Client, error) {
	if teamID == "" || keyID == "" || bundleID == "" {
		return nil, errors.New("team id, key id and bundle id are required")
	}
	key, err := parseP8(p8PEM)
	if err != nil {
		return nil, err
	}
	return &Client{
		teamID:   teamID,
		keyID:    keyID,
		key:      key,
		bundleID: bundleID,
		http: &http.Client{
			Timeout:   15 * time.Second,
			Transport: &http.Transport{ForceAttemptHTTP2: true},
		},
		hosts: map[string]string{"production": productionHost, "sandbox": sandboxHost},
		now:   time.Now,
	}, nil
}

func parseP8(p8PEM string) (*ecdsa.PrivateKey, error) {
	text := strings.ReplaceAll(strings.TrimSpace(p8PEM), `\n`, "\n")
	block, _ := pem.Decode([]byte(text))
	if block == nil {
		return nil, errors.New("APNs key is not PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parsing APNs key: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("APNs key is not an EC key")
	}
	return key, nil
}

// Topic is the APNs topic for widget pushes: the app's bundle id plus the
// widgets push-type suffix.
func (c *Client) Topic() string { return c.bundleID + ".push-type.widgets" }

// providerToken returns a cached ES256 JWT, minting a new one when the old
// one is near Apple's one-hour limit.
func (c *Client) providerToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now()
	if c.jwt != "" && now.Before(c.jwtUntil) {
		return c.jwt, nil
	}
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": c.keyID})
	claims, _ := json.Marshal(map[string]any{"iss": c.teamID, "iat": now.Unix()})
	signing := b64(header) + "." + b64(claims)
	digest := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, c.key, digest[:])
	if err != nil {
		return "", fmt.Errorf("signing APNs token: %w", err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	c.jwt = signing + "." + b64(sig)
	c.jwtUntil = now.Add(jwtLifetime)
	return c.jwt, nil
}

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// Send delivers one widget push. environment is "production" (App Store,
// TestFlight) or "sandbox" (Xcode builds).
func (c *Client) Send(ctx context.Context, deviceToken, environment string, payload []byte) error {
	host, ok := c.hosts[environment]
	if !ok {
		return fmt.Errorf("unknown APNs environment %q", environment)
	}
	token, err := c.providerToken()
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, host+"/3/device/"+deviceToken, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+token)
	req.Header.Set("apns-topic", c.Topic())
	req.Header.Set("apns-push-type", "widgets")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-expiration", fmt.Sprint(c.now().Add(10*time.Minute).Unix()))
	req.Header.Set("content-type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("apns: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	var apnsErr struct {
		Reason string `json:"reason"`
	}
	_ = json.Unmarshal(body, &apnsErr)
	switch {
	case resp.StatusCode == http.StatusGone,
		apnsErr.Reason == "BadDeviceToken",
		apnsErr.Reason == "DeviceTokenNotForTopic",
		apnsErr.Reason == "Unregistered":
		return fmt.Errorf("%w: %s (%d)", ErrBadToken, apnsErr.Reason, resp.StatusCode)
	}
	return fmt.Errorf("apns: %d %s", resp.StatusCode, apnsErr.Reason)
}

// ContentChanged is the widget push payload: no content, just the signal.
var ContentChanged = []byte(`{"aps":{"content-changed":true}}`)

// verifyJWT is a test hook: checks a provider token's signature with the
// public key. Not used in production paths.
func verifyJWT(token string, pub *ecdsa.PublicKey) bool {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return false
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return false
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	return ecdsa.Verify(pub, digest[:], r, s)
}

var _ crypto.Signer = (*ecdsa.PrivateKey)(nil)
