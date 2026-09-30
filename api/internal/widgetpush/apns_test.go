package widgetpush

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testKeyPEM(t *testing.T) (string, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	return string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})), key
}

func TestNewClientParsesP8AndEscapedNewlines(t *testing.T) {
	pemText, _ := testKeyPEM(t)
	c, err := NewClient("TEAM123456", "KEY1234567", pemText, "com.donwb.BeachRampTV")
	require.NoError(t, err)
	assert.Equal(t, "com.donwb.BeachRampTV.push-type.widgets", c.Topic())

	// An env var often carries the key with literal \n sequences.
	escaped := strings.ReplaceAll(pemText, "\n", `\n`)
	_, err = NewClient("TEAM123456", "KEY1234567", escaped, "com.donwb.BeachRampTV")
	assert.NoError(t, err)

	_, err = NewClient("TEAM123456", "KEY1234567", "not a key", "com.donwb.BeachRampTV")
	assert.Error(t, err)
	_, err = NewClient("", "KEY1234567", pemText, "com.donwb.BeachRampTV")
	assert.Error(t, err)
}

func TestProviderTokenIsSignedAndCached(t *testing.T) {
	pemText, key := testKeyPEM(t)
	c, err := NewClient("TEAM123456", "KEY1234567", pemText, "com.donwb.BeachRampTV")
	require.NoError(t, err)
	now := time.Date(2026, 9, 30, 9, 0, 0, 0, time.UTC)
	c.now = func() time.Time { return now }

	first, err := c.providerToken()
	require.NoError(t, err)
	assert.True(t, verifyJWT(first, &key.PublicKey), "ES256 signature verifies with the public key")

	second, _ := c.providerToken()
	assert.Equal(t, first, second, "reused inside the lifetime")

	now = now.Add(jwtLifetime + time.Minute)
	third, _ := c.providerToken()
	assert.NotEqual(t, first, third, "minted again past the lifetime")
}

func TestSendHeadersAndErrors(t *testing.T) {
	pemText, _ := testKeyPEM(t)
	var got atomic.Value
	status := int32(200)
	body := atomic.Value{}
	body.Store("")
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got.Store(r.Clone(context.Background()))
		w.WriteHeader(int(atomic.LoadInt32(&status)))
		_, _ = w.Write([]byte(body.Load().(string)))
	}))
	defer srv.Close()

	c, err := NewClient("TEAM123456", "KEY1234567", pemText, "com.donwb.BeachRampTV")
	require.NoError(t, err)
	c.http = srv.Client()
	c.hosts = map[string]string{"production": srv.URL, "sandbox": srv.URL}

	require.NoError(t, c.Send(context.Background(), "abcdef0123", "production", ContentChanged))
	req := got.Load().(*http.Request)
	assert.Equal(t, "/3/device/abcdef0123", req.URL.Path)
	assert.Equal(t, "widgets", req.Header.Get("apns-push-type"))
	assert.Equal(t, "com.donwb.BeachRampTV.push-type.widgets", req.Header.Get("apns-topic"))
	assert.True(t, strings.HasPrefix(req.Header.Get("authorization"), "bearer "))

	atomic.StoreInt32(&status, 410)
	body.Store(`{"reason":"Unregistered"}`)
	err = c.Send(context.Background(), "abcdef0123", "production", ContentChanged)
	assert.ErrorIs(t, err, ErrBadToken)

	atomic.StoreInt32(&status, 400)
	body.Store(`{"reason":"BadDeviceToken"}`)
	assert.ErrorIs(t, c.Send(context.Background(), "abcdef0123", "sandbox", ContentChanged), ErrBadToken)

	atomic.StoreInt32(&status, 500)
	body.Store(`{"reason":"InternalServerError"}`)
	err = c.Send(context.Background(), "abcdef0123", "production", ContentChanged)
	assert.Error(t, err)
	assert.False(t, strings.Contains(err.Error(), ErrBadToken.Error()), "a server error is not a bad token")

	assert.Error(t, c.Send(context.Background(), "abcdef0123", "staging", ContentChanged))
}
