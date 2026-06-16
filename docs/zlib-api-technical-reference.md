# Z-Library Go Client — Technical API Reference

> **Library:** `github.com/heartleo/zlib`  
> **Version tested:** v0.0.5 (commit `1323aab`, 2026-06-15)  
> **Go module:** `github.com/heartleo/zlib`  
> **License:** MIT  
> **Approach:** HTML scraping + Cloudflare challenge solver  
> **Default domain:** `https://z-lib.sk`

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Client                         │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ http.Client │  │ cookiejar │  │ challenge    │  │
│  │ (gzip,     │  │ (session  │  │ solver       │  │
│  │  cookies)  │  │  state)   │  │ (SHA-1 PoW)  │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
│                                                  │
│  State: domain, loginDomain, cookies, loggedIn   │
└─────────────────────────────────────────────────┘
         │
         ▼ HTTP GET/POST (gzip, browser UA)
┌─────────────────────────────────────────────────┐
│              z-lib.sk (Cloudflare)               │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ /rpc.php │  │ /s/{q}   │  │ /dl/{token}   │  │
│  │ (login)  │  │ (search) │  │ (download)    │  │
│  └──────────┘  └──────────┘  └───────────────┘  │
└─────────────────────────────────────────────────┘
```

**Key design decisions:**
- Cookie-based session (not token-based), stored in `http.cookiejar`
- All GET requests go through a central `get()` method that handles gzip decompression, Cloudflare challenge solving, and session-expiry detection
- Login POST goes directly (bypasses challenge) — the `/rpc.php` endpoint doesn't require it
- HTML parsed via `github.com/PuerkitoBio/goquery` (jQuery-like selectors)

---

## 2. Client Lifecycle

### 2.1 Initialization

```go
c := zlib.NewClient()                              // defaults: z-lib.sk, 180s timeout
c := zlib.NewClient(zlib.WithDomain("https://...")) // custom domain
c := zlib.NewClient(zlib.WithProxy("http://127.0.0.1:7890")) // SOCKS/HTTP proxy
c := zlib.NewClient(zlib.WithOnion("socks5://127.0.0.1:9050")) // Tor .onion
```

**Env vars (read automatically):**
```
ZLIB_DOMAIN=https://z-lib.sk    # override default domain
ZLIB_PROXY=http://127.0.0.1:7890 # HTTP/SOCKS proxy
```

### 2.2 State Transitions

```
NewClient() ──► loggedIn=false, cookies={}
     │
     ▼ Login(email, pass)
     │
     ▼ loggedIn=true, cookies={remix_userid, remix_userkey, ...}
     │
     ├─► Search() / FetchBook() / Download() / GetLimits() ...
     │
     ▼ Logout()
     │
     ▼ loggedIn=false, cookies={}, new cookie jar
```

**Session expiry:** When a `get()` response contains `id="loginForm"`, the library returns `ErrSessionExpired`. The caller must call `Login()` again.

---

## 3. Domain & URL Structure

| Constant | Value |
|----------|-------|
| `DefaultDomain` | `https://z-lib.sk` |
| `TorDomain` | `http://bookszlibb74ugqojhzhg2a63w5i2atv5bqarulgczawnbmsb6s6qead.onion` |

### URL Patterns

| Purpose | Path Pattern | Method |
|---------|-------------|--------|
| Login | `{domain}/rpc.php` | POST |
| Search | `{domain}/s/{query}?page=N&...` | GET |
| Full-text search | `{domain}/fulltext/{query}?type=words\|phrase&...` | GET |
| Book detail | `{domain}/book/{bookID}` | GET |
| Downloads page | `{domain}/users/downloads` | GET |
| History page | `{domain}/users/dstats.php?date_from=&date_to=&page=N` | GET |
| Downloads paginated | `{domain}/users/downloads?page=N` | GET |
| Download file | `{domain}/dl/{token}` or `{domain}/file/{token}` | GET |

---

## 4. Authentication Flow

### 4.1 Login Request

```
POST {domain}/rpc.php
Content-Type: application/x-www-form-urlencoded
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36

isModal=true
email={email}
password={password}
site_mode=books
action=login
isSingleLogin=1
redirectUrl=
gg_json_mode=1
```

### 4.2 Login Response (success)

```json
{
  "response": {}
}
```

Cookies returned via `Set-Cookie`:
- `remix_userid` — numeric user ID
- `remix_userkey` — session token (alphanumeric)

### 4.3 Login Response (failure)

```json
{
  "errors": [],
  "response": {
    "validationError": true,
    "fields": ["email", "password"],
    "message": "Incorrect email or password"
  }
}
```

Error returned: `zlibrary: login failed: true`

**Note:** The `gg_json_mode=1` parameter requests JSON mode. Without it, the server returns HTML. The library expects JSON and will fail with a parse error on HTML responses.

---

## 5. Cloudflare Challenge Solver

### 5.1 Detection

The `get()` method checks if the response HTML matches:
```go
var challengeRe = regexp.MustCompile(`'([0-9A-Fa-f]{40})','c_token='`)
```

And the page must be `< 20000` bytes (challenge pages are small). The homepage at `z-lib.sk/` returns HTTP 503 with a JS challenge.

### 5.2 Algorithm (SHA-1 Proof of Work)

```
Input:  c = 40-char hex string extracted from JS
        n1 = int(c[0], base 16)  // e.g., '6' → 6

Find smallest i (0..9,999,999) such that:
    sha1(c + strconv.Itoa(i))[n1]   == 0xb0  AND
    sha1(c + strconv.Itoa(i))[n1+1] == 0x0b

Output: c_token = c + strconv.Itoa(i)
```

The token is stored as cookie `c_token` and the request is retried. The brute-force loop runs up to 10 million iterations.

### 5.3 Retry Mechanism

```go
func (c *Client) get(rawURL string) (string, error) {
    // ... make request ...
    if isChallengePage(html) {
        token, err := solveChallenge(html)
        // on success:
        c.cookies["c_token"] = token
        return c.get(rawURL)  // retry once with token
    }
    // ...
}
```

---

## 6. Search API

### 6.1 Standard Search

```go
func (c *Client) Search(query string, page, count int, opts *SearchOptions) (SearchResult, error)
```

**HTTP:**
```
GET {domain}/s/{url-encoded-query}?page={page}&e={exact}&yearFrom={from}&yearTo={to}&languages%5B%5D={lang}&extensions%5B%5D={ext}
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `query` | string | Search term (required, non-empty) |
| `page` | int | Page number, 1-based |
| `count` | int | Results per page (1–50, default 10) |
| `opts.Exact` | bool | Exact match (`&e=1`) |
| `opts.FromYear` | int | Year range start |
| `opts.ToYear` | int | Year range end |
| `opts.Languages` | []Language | Filter by language |
| `opts.Extensions` | []Extension | Filter by file format |

**Supported Languages:** `english`, `chinese`, `russian`, `french`, `german`, `spanish`, `japanese`, `korean`, `italian`, `portuguese`, `arabic`, `dutch`, `polish`, `turkish`, `hindi`

**Supported Extensions:** `PDF`, `EPUB`, `FB2`, `MOBI`, `AZW3`, `TXT`, `RTF`, `DJVU`, `LIT`, `DJV`, `AZW`

**Pagination:** Extracted from `<script>` tag via regex `pagesTotal:\s*(\d+)`

### 6.2 Full-Text Search

```go
func (c *Client) FullTextSearch(query string, page, count int, opts *FullTextSearchOptions) (SearchResult, error)
```

```
GET {domain}/fulltext/{query}?type={words|phrase}&...
```

- `type=words` — default, any word match
- `type=phrase` — exact phrase matching (requires ≥ 2 words, enforced client-side)

### 6.3 HTML Parsing

Parses `#searchResultBox` container. Each result is a `<z-bookcard>` custom element inside `.book-item`:

```html
<z-bookcard id="12345" isbn="..." href="/book/..." 
            publisher="..." year="2024" language="english"
            extension="pdf" filesize="10 MB" rating="4.5" quality="5">
  <img slot="cover" data-src="https://covers.z-lib.sk/...jpg">
  <div slot="title">Book Title</div>
  <div slot="author">Author Name</div>
</z-bookcard>
```

## 7. Book Detail

```go
func (c *Client) FetchBook(id string) (Book, error)
func (c *Client) FetchBookDetails(ids []string) map[string]Book  // concurrent
```

```
GET {domain}/book/{bookID}
```

Parses the book page HTML using selectors:

| Field | Selector |
|-------|----------|
| ID, Title, Cover | `z-cover[id][title] img.image[src]` |
| Authors | `i.authors a` |
| Description | `#bookDescriptionBox` |
| Year | `.property_year .property_value` |
| Edition | `.property_edition .property_value` |
| Publisher | `.property_publisher .property_value` |
| Language | `.property_language .property_value` |
| Categories | `.property_categories .property_value` |
| Extension, Size | `.property__file .property_value` (split on `,`) |
| Rating | `.book-rating` |
| Download URL | `a.addDownloadedBook[href]`, or `a[href*="/dl/"]`, or `a[href*="/file/"]` |

`FetchBookDetails` runs concurrent goroutines (one per ID), collecting results via channel.

---

## 8. Download Flow

```go
func (c *Client) Download(downloadURL, destDir string, progressFn func(written, total int64)) (DownloadResult, error)
func (c *Client) DownloadWithContext(ctx context.Context, downloadURL, destDir string, ...) (DownloadResult, error)
```

**Flow:**
1. Creates a **separate `http.Client` with no timeout** (CDN can be slow)
2. Sends GET to download URL with cookies and `Referer: {domain}/`
3. Follows HTTP 301/302 redirects automatically
4. Extracts filename from `Content-Disposition` header or URL path
5. Cleans filename: strips trailing ` (z-library.sk, ...)` suffix
6. Streams response body to disk in 32KB chunks, calling `progressFn` after each chunk
7. On context cancellation: removes incomplete file

**DownloadResult:**
```go
type DownloadResult struct {
    FilePath string  // absolute path to downloaded file
    Size     int64   // bytes written
}
```

---

## 9. Profile & Limits

```go
func (c *Client) GetLimits() (DownloadLimit, error)
```

```
GET {domain}/users/downloads
```

Parses `.dstats-info` container:

```go
type DownloadLimit struct {
    DailyAmount    int    // downloads used today
    DailyAllowed   int    // daily quota
    DailyRemaining int    // allowed - amount
    DailyReset     string // e.g. "12h 34m"
}
```

Parsed from format: `{used}/{total}` in `.d-count`, reset timer in `.d-reset`.

### Download History

```go
func (c *Client) DownloadHistory(page int) (DownloadHistoryResult, error)
```

Tries two URLs in sequence:
1. `{domain}/users/dstats.php?date_from=&date_to=&page={page}`
2. `{domain}/users/downloads?page={page}`

Parses `<tr>` rows, extracting: book title, book URL, download URL, date, extension, size. Deduplicates via composite key.

---

## 10. Kindle Send-to-Kindle

```go
func SendToKindle(filePath string, cfg KindleConfig, smtpPassword string) error
```

**Configuration:**
```go
type KindleConfig struct {
    To       string // kindle email address
    From     string // sender email
    SMTPHost string // smtp server
    SMTPPort int    // smtp port
}
```

**Validation:**
- File extension must be: `.epub`, `.pdf`, `.txt`, `.doc`, `.docx`, `.html`, `.htm`, `.rtf`, `.jpg`, `.jpeg`, `.png`, `.bmp`, `.gif`
- File size ≤ 200 MB (Amazon limit)
- Gmail SMTP: estimated base64-encoded message size ≤ 25 MB

**MIME construction:** `multipart/mixed` with `Content-Transfer-Encoding: base64`. Unicode filenames encoded via `filename*=UTF-8''...` (RFC 5987). SMTP auth via `PLAIN`.

---

## 11. Data Models

```go
type Book struct {
    ID          string   `json:"id"`
    ISBN        string   `json:"isbn,omitempty"`
    URL         string   `json:"url"`
    Cover       string   `json:"cover,omitempty"`
    Name        string   `json:"name"`
    Authors     []string `json:"authors,omitempty"`
    Publisher   string   `json:"publisher,omitempty"`
    Year        string   `json:"year,omitempty"`
    Language    string   `json:"language,omitempty"`
    Extension   string   `json:"extension,omitempty"`
    Size        string   `json:"size,omitempty"`
    Rating      string   `json:"rating,omitempty"`
    Quality     string   `json:"quality,omitempty"`
    Description string   `json:"description,omitempty"`
    Categories  string   `json:"categories,omitempty"`
    Edition     string   `json:"edition,omitempty"`
    DownloadURL string   `json:"download_url,omitempty"`
}

type SearchResult struct {
    Books      []Book `json:"books"`
    Page       int    `json:"page"`
    TotalPages int    `json:"total_pages"`
}

type DownloadLimit struct {
    DailyAmount    int    `json:"daily_amount"`
    DailyAllowed   int    `json:"daily_allowed"`
    DailyRemaining int    `json:"daily_remaining"`
    DailyReset     string `json:"daily_reset"`
}

type DownloadHistoryItem struct {
    Name        string `json:"name"`
    URL         string `json:"url"`
    DownloadURL string `json:"download_url,omitempty"`
    Extension   string `json:"extension,omitempty"`
    Size        string `json:"size,omitempty"`
    Date        string `json:"date"`
}

type DownloadHistoryResult struct {
    Items      []DownloadHistoryItem `json:"items"`
    Page       int                   `json:"page"`
    TotalPages int                   `json:"total_pages"`
}

type SearchOptions struct {
    Exact      bool
    FromYear   int
    ToYear     int
    Languages  []Language
    Extensions []Extension
}

type FullTextSearchOptions struct {
    SearchOptions
    Phrase bool // requires ≥ 2 words
}
```

---

## 12. Error Types

| Error | Meaning |
|-------|---------|
| `ErrLoginFailed` | Login request failed or invalid credentials |
| `ErrNotLoggedIn` | Method called before `Login()` |
| `ErrNoDomain` | No working domain configured |
| `ErrEmptyQuery` | Search query is empty string |
| `ErrNoID` | Book ID is empty |
| `ErrInvalidProxy` | Proxy configuration invalid |
| `ErrParseFailed` | HTML parsing failed (site structure changed?) |
| `ErrSessionExpired` | Server returned login page — session cookie expired |
| `ErrPhraseMinWords` | Full-text phrase search requires ≥ 2 words |

---

## 13. Environment Variables

| Variable | Purpose |
|----------|---------|
| `ZLIB_DOMAIN` | Override default domain (default: `https://z-lib.sk`) |
| `ZLIB_PROXY` | HTTP/SOCKS proxy URL (e.g. `http://127.0.0.1:7890`) |

---

## 14. HTTP Headers

All requests use these headers to mimic a browser:

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8
Accept-Language: en-US,en;q=0.9
Accept-Encoding: gzip
Sec-Fetch-Dest: document
Sec-Fetch-Mode: navigate
Sec-Fetch-Site: none
Sec-Fetch-User: ?1
Upgrade-Insecure-Requests: 1
```

Downloads additionally send: `Referer: {domain}/`

---

## 15. Dependencies

| Package | Purpose |
|---------|---------|
| `github.com/PuerkitoBio/goquery` | HTML parsing (jQuery-like selectors) |
| `github.com/spf13/cobra` | CLI framework (cmd only) |
| `github.com/charmbracelet/bubbletea` | TUI framework (cmd only) |
| `github.com/charmbracelet/huh` | Interactive forms (cmd only) |
| `github.com/charmbracelet/lipgloss` | Terminal styling (cmd only) |
| `golang.org/x/net` | Extended net libraries |

---

## 16. Domain Status (2026-06-15)

| Domain | Status | Notes |
|--------|--------|-------|
| `z-lib.sk` | ✅ Working | Homepage returns 503 (JS challenge); `/rpc.php` returns JSON; all paths verified |
| `z-lib.id` | ⚠️ Partial | Homepage accessible, but different structure — no `/rpc.php`, no `/eapi/` |
| `1lib.sk` | ❌ Down | Returns 503 |
| `singlelogin.re` | ❌ Hijacked | Now an adult site |
| `singlelogin.se` | ❌ Dead | DNS doesn't resolve |

---

## 17. Test Suite

21 tests, 100% pass rate. Tests use `httptest.NewServer` for mocking:

| Test | What It Verifies |
|------|-----------------|
| `TestLogin_Success` | Login parses JSON response, extracts cookies |
| `TestLogin_ValidationError` | Failed login returns error |
| `TestFetchBook` | Book detail HTML parsing |
| `TestWithDomain` | Custom domain configuration |
| `TestParseSearchResults` | Search result extraction from HTML |
| `TestParseSearchResults_NotFound` | Empty search handling |
| `TestParseBookDetail` | Full book detail parsing |
| `TestParseDownloadHistory` | History page parsing |
| `TestParseDownloadLimits` | Quota parsing |
| `TestExtensionString` / `TestOrderOptionString` | Enum stringification |
| `TestSetDefaultDomain` | Domain normalization |
| `TestNewClientAppliesProxyFromEnv` | Proxy env var |
| `TestValidateKindleAttachment*` | Kindle file validation |
