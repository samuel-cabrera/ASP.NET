package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

// Obtiene la IP del cliente considerando proxies
func getClientIP(r *http.Request) string {
	if x := r.Header.Get("X-Forwarded-For"); x != "" {
		parts := strings.Split(x, ",")
		if ip := strings.TrimSpace(parts[0]); ip != "" {
			return ip
		}
	}
	if ip := r.Header.Get("X-Real-IP"); ip != "" {
		return ip
	}
	if ip := r.Header.Get("CF-Connecting-IP"); ip != "" {
		return ip
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// Muestra la página HTML con fecha e IP
func homeHandler(w http.ResponseWriter, r *http.Request) {
	now := time.Now()
	dateFriendly := now.Format("2006-01-02 15:04:05 Monday")
	dateISO := now.Format(time.RFC3339)
	clientIP := getClientIP(r)

	html := fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
<title>Info Cliente - Go Server</title>
<meta charset="UTF-8">
<style>
body { font-family: Arial, sans-serif; max-width: 600px; margin: 40px auto; }
.box { background: #f0f8ff; padding: 20px; margin-bottom: 20px; border-left: 4px solid #007acc; }
</style>
</head>
<body>
<h1>🕒 Fecha e IP del Cliente</h1>
<div class="box">
  <h2>Fecha del Servidor</h2>
  <p><strong>Legible:</strong> %s</p>
  <p><strong>ISO 8601:</strong> %s</p>
  <p><strong>Unix:</strong> %d</p>
</div>
<div class="box">
  <h2>Datos del Cliente</h2>
  <p><strong>IP:</strong> %s</p>
  <p><strong>User-Agent:</strong> %s</p>
  <p><strong>Método:</strong> %s</p>
  <p><strong>URL:</strong> %s</p>
</div>
</body>
</html>
`, dateFriendly, dateISO, now.Unix(), clientIP, r.Header.Get("User-Agent"), r.Method, r.URL.Path)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, html)
	log.Printf("IP %s - %s", clientIP, r.URL.Path)
}

// API JSON con datos
func apiHandler(w http.ResponseWriter, r *http.Request) {
	now := time.Now()
	resp := map[string]any{
		"timestamp": now.Format(time.RFC3339),
		"unix":      now.Unix(),
		"ip":        getClientIP(r),
		"method":    r.Method,
		"path":      r.URL.Path,
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_ = json.NewEncoder(w).Encode(resp)
	log.Printf("API hit from %s", resp["ip"])
}

func main() {
	http.HandleFunc("/", homeHandler)
	http.HandleFunc("/api", apiHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port

	log.Printf("Servidor escuchando en %s …", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}