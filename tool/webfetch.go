package tool

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/net/html"
)

const (
	MaxResponseSize       = 5 * 1024 * 1024 // 5MB
	DefaultWebTimeout     = 30 * time.Second
	MaxWebTimeout         = 120 * time.Second
	DefaultWebFetchFormat = "markdown"
)

// WebFetchTool creates the web fetch tool
func WebFetchTool() *ToolDefinition {
	return &ToolDefinition{
		ID:   "webfetch",
		Name: "webfetch",
		Description: `Fetches content from a specified URL and processes it.

Usage:
- Takes a URL and optional format parameter
- Fetches the URL content, converts HTML to markdown or text based on format
- Returns the fetched content with appropriate formatting
- Use this tool when you need to retrieve web content

Usage notes:
  - The URL must be a fully-formed valid URL starting with http:// or https://
  - HTTP URLs will be automatically upgraded to HTTPS
  - The format parameter can be "text", "markdown", or "html" (defaults to "markdown")
  - This tool is read-only and does not modify any files
  - Results may be truncated if the content is very large (exceeds 5MB limit)
  - Default timeout is 30 seconds, maximum is 120 seconds`,
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"url": map[string]interface{}{
					"type":        "string",
					"description": "The URL to fetch content from",
				},
				"format": map[string]interface{}{
					"type":        "string",
					"enum":        []string{"text", "markdown", "html"},
					"description": "The format to return the content in (text, markdown, or html). Defaults to markdown.",
				},
				"timeout": map[string]interface{}{
					"type":        "number",
					"description": "Optional timeout in seconds (max 120)",
				},
			},
			"required": []string{"url"},
		},
		Execute: executeWebFetch,
	}
}

func executeWebFetch(params map[string]interface{}, ctx ToolContext) (ToolResult, error) {
	url, ok := params["url"].(string)
	if !ok {
		return ToolResult{}, fmt.Errorf("url parameter is required")
	}

	// Validate URL
	if !strings.HasPrefix(url, "http://") && !strings.HasPrefix(url, "https://") {
		return ToolResult{}, fmt.Errorf("URL must start with http:// or https://")
	}

	// Upgrade HTTP to HTTPS
	if strings.HasPrefix(url, "http://") {
		url = "https://" + strings.TrimPrefix(url, "http://")
	}

	// Get format parameter (default to markdown)
	format := DefaultWebFetchFormat
	if formatParam, ok := params["format"].(string); ok {
		format = formatParam
	}

	// Get timeout
	timeout := DefaultWebTimeout
	if timeoutParam, ok := params["timeout"].(float64); ok {
		timeout = time.Duration(timeoutParam) * time.Second
		if timeout > MaxWebTimeout {
			timeout = MaxWebTimeout
		}
	}

	// Create HTTP client with timeout
	client := &http.Client{
		Timeout: timeout,
	}

	// Build Accept header based on requested format
	var acceptHeader string
	switch format {
	case "markdown":
		acceptHeader = "text/markdown;q=1.0, text/x-markdown;q=0.9, text/plain;q=0.8, text/html;q=0.7, */*;q=0.1"
	case "text":
		acceptHeader = "text/plain;q=1.0, text/markdown;q=0.9, text/html;q=0.8, */*;q=0.1"
	case "html":
		acceptHeader = "text/html;q=1.0, application/xhtml+xml;q=0.9, text/plain;q=0.8, text/markdown;q=0.7, */*;q=0.1"
	default:
		acceptHeader = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
	}

	// Create request
	req, err := http.NewRequestWithContext(ctx.Abort, "GET", url, nil)
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to create request: %v", err)
	}

	// Set headers
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", acceptHeader)
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")

	// Execute request
	resp, err := client.Do(req)
	if err != nil {
		return ToolResult{}, fmt.Errorf("request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return ToolResult{}, fmt.Errorf("request failed with status code: %d", resp.StatusCode)
	}

	// Check content length
	if resp.ContentLength > MaxResponseSize {
		return ToolResult{}, fmt.Errorf("response too large (exceeds 5MB limit)")
	}

	// Read response body with size limit
	body, err := io.ReadAll(io.LimitReader(resp.Body, MaxResponseSize+1))
	if err != nil {
		return ToolResult{}, fmt.Errorf("failed to read response: %v", err)
	}

	if len(body) > MaxResponseSize {
		return ToolResult{}, fmt.Errorf("response too large (exceeds 5MB limit)")
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "unknown"
	}

	title := fmt.Sprintf("%s (%s)", url, contentType)

	// Process content based on requested format
	var output string
	isHTML := strings.Contains(strings.ToLower(contentType), "text/html")

	switch format {
	case "markdown":
		if isHTML {
			output, err = convertHTMLToMarkdown(body)
			if err != nil {
				return ToolResult{}, fmt.Errorf("failed to convert HTML to markdown: %v", err)
			}
		} else {
			output = string(body)
		}

	case "text":
		if isHTML {
			output, err = extractTextFromHTML(body)
			if err != nil {
				return ToolResult{}, fmt.Errorf("failed to extract text from HTML: %v", err)
			}
		} else {
			output = string(body)
		}

	case "html":
		output = string(body)

	default:
		output = string(body)
	}

	return ToolResult{
		Title:    title,
		Output:   output,
		Metadata: map[string]interface{}{},
	}, nil
}

// extractTextFromHTML extracts plain text content from HTML
func extractTextFromHTML(htmlContent []byte) (string, error) {
	doc, err := html.Parse(bytes.NewReader(htmlContent))
	if err != nil {
		return "", err
	}

	var text strings.Builder
	var extract func(*html.Node, bool)
	extract = func(n *html.Node, skip bool) {
		// Skip content in script, style, noscript, iframe, object, embed tags
		if n.Type == html.ElementNode {
			switch n.Data {
			case "script", "style", "noscript", "iframe", "object", "embed":
				skip = true
			}
		}

		if n.Type == html.TextNode && !skip {
			text.WriteString(n.Data)
		}

		for c := n.FirstChild; c != nil; c = c.NextSibling {
			extract(c, skip)
		}
	}

	extract(doc, false)
	return strings.TrimSpace(text.String()), nil
}

// convertHTMLToMarkdown converts HTML to markdown format
func convertHTMLToMarkdown(htmlContent []byte) (string, error) {
	doc, err := html.Parse(bytes.NewReader(htmlContent))
	if err != nil {
		return "", err
	}

	var md strings.Builder
	var convert func(*html.Node, int)

	convert = func(n *html.Node, depth int) {
		// Skip script, style, meta, link tags
		if n.Type == html.ElementNode {
			switch n.Data {
			case "script", "style", "meta", "link":
				return
			}
		}

		if n.Type == html.ElementNode {
			switch n.Data {
			case "h1":
				md.WriteString("\n# ")
			case "h2":
				md.WriteString("\n## ")
			case "h3":
				md.WriteString("\n### ")
			case "h4":
				md.WriteString("\n#### ")
			case "h5":
				md.WriteString("\n##### ")
			case "h6":
				md.WriteString("\n###### ")
			case "p":
				md.WriteString("\n\n")
			case "br":
				md.WriteString("  \n")
			case "hr":
				md.WriteString("\n---\n")
			case "strong", "b":
				md.WriteString("**")
			case "em", "i":
				md.WriteString("*")
			case "code":
				md.WriteString("`")
			case "pre":
				md.WriteString("\n```\n")
			case "a":
				// Handle links
				for _, attr := range n.Attr {
					if attr.Key == "href" {
						md.WriteString("[")
						break
					}
				}
			case "ul", "ol":
				md.WriteString("\n")
			case "li":
				md.WriteString("\n- ")
			}
		}

		if n.Type == html.TextNode {
			md.WriteString(n.Data)
		}

		// Process children
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			convert(c, depth+1)
		}

		// Closing tags
		if n.Type == html.ElementNode {
			switch n.Data {
			case "strong", "b":
				md.WriteString("**")
			case "em", "i":
				md.WriteString("*")
			case "code":
				md.WriteString("`")
			case "pre":
				md.WriteString("\n```\n")
			case "a":
				// Handle links
				for _, attr := range n.Attr {
					if attr.Key == "href" {
						md.WriteString("](")
						md.WriteString(attr.Val)
						md.WriteString(")")
						break
					}
				}
			}
		}
	}

	convert(doc, 0)
	return strings.TrimSpace(md.String()), nil
}
