package main

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// NarInfo represents the metadata parsed from a .narinfo file
type NarInfo struct {
	StorePath   string   `json:"store_path"`
	URL         string   `json:"url"`
	Compression string   `json:"compression"`
	References  []string `json:"references"`
	NarSize     int64    `json:"nar_size"`
	NarHash     string   `json:"nar_hash"`
}

// SymlinkMetadata records symlinks that need to be virtually declared
type SymlinkMetadata struct {
	Path   string `json:"path"`
	Target string `json:"target"`
}

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: nix_extractor <hash> <output_dir>")
		os.Exit(1)
	}

	hash := os.Args[1]
	outputDir := os.Args[2]

	fmt.Printf("=== Starting Nix Extractor for Hash: %s ===\n", hash)

	// 1. Fetch and parse .narinfo
	narInfo, err := fetchNarInfo(hash)
	if err != nil {
		fmt.Printf("Error fetching narinfo: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Parsed NarInfo:\n  StorePath: %s\n  URL: %s\n  References: %v\n", 
		narInfo.StorePath, narInfo.URL, narInfo.References)

	// Ensure output directory exists
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		fmt.Printf("Error creating output dir: %v\n", err)
		os.Exit(1)
	}

	// 2. Download and Decompress NAR stream
	narReader, cmd, err := downloadAndDecompress(narInfo.URL)
	if err != nil {
		fmt.Printf("Error starting download/decompression: %v\n", err)
		os.Exit(1)
	}
	defer narReader.Close()

	// 3. Parse and Unpack NAR
	symlinks, err := unpackNar(narReader, outputDir)
	if err != nil {
		fmt.Printf("Error unpacking NAR: %v\n", err)
		os.Exit(1)
	}

	// Wait for decompression command to finish
	if cmd != nil {
		_ = cmd.Wait()
	}

	// 4. Save symlink metadata and references as JSON
	metadataFile := filepath.Join(outputDir, "_nix_metadata.json")
	metadata := map[string]interface{}{
		"references": narInfo.References,
		"symlinks":   symlinks,
		"store_path": narInfo.StorePath,
	}

	metaBytes, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		fmt.Printf("Error marshaling metadata: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile(metadataFile, metaBytes, 0644); err != nil {
		fmt.Printf("Error writing metadata file: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("=== Extraction Completed Successfully! ===\n")
}

// fetchNarInfo downloads and parses the .narinfo file
func fetchNarInfo(hash string) (*NarInfo, error) {
	url := fmt.Sprintf("https://cache.nixos.org/%s.narinfo", hash)
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("bad HTTP status: %d", resp.StatusCode)
	}

	info := &NarInfo{}
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ": ", 2)
		if len(parts) < 2 {
			continue
		}
		key, val := parts[0], parts[1]
		switch key {
		case "StorePath":
			info.StorePath = val
		case "URL":
			info.URL = val
		case "Compression":
			info.Compression = val
		case "References":
			if val != "" {
				info.References = strings.Fields(val)
			}
		case "NarSize":
			fmt.Sscanf(val, "%d", &info.NarSize)
		case "NarHash":
			info.NarHash = val
		}
	}

	return info, scanner.Err()
}

// downloadAndDecompress streams the download into `xz` for fast decompression
func downloadAndDecompress(relURL string) (io.ReadCloser, *exec.Cmd, error) {
	url := fmt.Sprintf("https://cache.nixos.org/%s", relURL)
	resp, err := http.Get(url)
	if err != nil {
		return nil, nil, err
	}

	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, nil, fmt.Errorf("bad HTTP status: %d", resp.StatusCode)
	}

	// Decompress xz using system `xz` command via pipes
	cmd := exec.Command("xz", "-d")
	cmd.Stdin = resp.Body

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		resp.Body.Close()
		return nil, nil, err
	}

	if err := cmd.Start(); err != nil {
		resp.Body.Close()
		return nil, nil, err
	}

	// Return a custom ReadCloser that closes both stdout and the HTTP body
	return &wrappedReader{
		Reader: stdout,
		closeFn: func() error {
			stdout.Close()
			return resp.Body.Close()
		},
	}, cmd, nil
}

type wrappedReader struct {
	io.Reader
	closeFn func() error
}

func (w *wrappedReader) Close() error {
	return w.closeFn()
}

// unpackNar parses the custom NAR file format from the stream
func unpackNar(r io.Reader, dest string) ([]SymlinkMetadata, error) {
	var symlinks []SymlinkMetadata

	// 1. Verify Magic
	magic, err := readString(r)
	if err != nil {
		return nil, fmt.Errorf("error reading magic: %w", err)
	}
	if magic != "nix-archive-1" {
		return nil, fmt.Errorf("invalid NAR magic: %s", magic)
	}

	// Helper function to recursively parse nodes
	var parseNode func(currentPath string) error
	parseNode = func(currentPath string) error {
		// Read "("
		tok, err := readString(r)
		if err != nil {
			return err
		}
		if tok != "(" {
			return fmt.Errorf("expected '(', got '%s'", tok)
		}

		// Read "type"
		tok, err = readString(r)
		if err != nil {
			return err
		}
		if tok != "type" {
			return fmt.Errorf("expected 'type', got '%s'", tok)
		}

		// Read node type
		nodeType, err := readString(r)
		if err != nil {
			return err
		}

		switch nodeType {
		case "regular":
			var isExecutable bool
			for {
				next, err := readString(r)
				if err != nil {
					return err
				}
				if next == ")" {
					break
				}
				if next == "executable" {
					isExecutable = true
					// Executable token is followed by empty string
					empty, err := readString(r)
					if err != nil {
						return err
					}
					if empty != "" {
						return fmt.Errorf("expected empty string after executable token, got '%s'", empty)
					}
				} else if next == "contents" {
					// Read file size
					var size uint64
					if err := binary.Read(r, binary.LittleEndian, &size); err != nil {
						return err
					}

					// Create output file
					f, err := os.Create(currentPath)
					if err != nil {
						return err
					}
					
					// Stream copy contents
					_, err = io.CopyN(f, r, int64(size))
					f.Close()
					if err != nil {
						return err
					}

					// Discard alignment padding
					pad := (8 - (size % 8)) % 8
					if pad > 0 {
						if _, err := io.CopyN(io.Discard, r, int64(pad)); err != nil {
							return err
						}
					}

					if isExecutable {
						os.Chmod(currentPath, 0755)
					} else {
						os.Chmod(currentPath, 0644)
					}
				} else {
					return fmt.Errorf("unexpected regular file token: '%s'", next)
				}
			}

		case "directory":
			if err := os.MkdirAll(currentPath, 0755); err != nil {
				return err
			}
			for {
				next, err := readString(r)
				if err != nil {
					return err
				}
				if next == ")" {
					break
				}
				if next != "entry" {
					return fmt.Errorf("expected 'entry', got '%s'", next)
				}

				// Read "("
				tok, err = readString(r)
				if err != nil {
					return err
				}
				if tok != "(" {
					return fmt.Errorf("expected '(', got '%s'", tok)
				}

				// Read "name"
				tok, err = readString(r)
				if err != nil {
					return err
				}
				if tok != "name" {
					return fmt.Errorf("expected 'name', got '%s'", tok)
				}

				entryName, err := readString(r)
				if err != nil {
					return err
				}

				// Read "node"
				tok, err = readString(r)
				if err != nil {
					return err
				}
				if tok != "node" {
					return fmt.Errorf("expected 'node', got '%s'", tok)
				}

				// Recursively parse entry node
				if err := parseNode(filepath.Join(currentPath, entryName)); err != nil {
					return err
				}

				// Read ")"
				tok, err = readString(r)
				if err != nil {
					return err
				}
				if tok != ")" {
					return fmt.Errorf("expected ')', got '%s'", tok)
				}
			}

		case "symlink":
			// Read "target"
			tok, err = readString(r)
			if err != nil {
				return err
			}
			if tok != "target" {
				return fmt.Errorf("expected 'target', got '%s'", tok)
			}

			targetPath, err := readString(r)
			if err != nil {
				return err
			}

			// Read ")"
			tok, err = readString(r)
			if err != nil {
				return err
			}
			if tok != ")" {
				return fmt.Errorf("expected ')', got '%s'", tok)
			}

			// Capture Symlink Virtually (relative to the destination root)
			relPath, _ := filepath.Rel(dest, currentPath)
			symlinks = append(symlinks, SymlinkMetadata{
				Path:   relPath,
				Target: targetPath,
			})

		default:
			return fmt.Errorf("unknown node type: %s", nodeType)
		}

		return nil
	}

	err = parseNode(dest)
	return symlinks, err
}

// readString reads a length-prefixed, 8-byte aligned string from the NAR stream
func readString(r io.Reader) (string, error) {
	var size uint64
	if err := binary.Read(r, binary.LittleEndian, &size); err != nil {
		return "", err
	}

	buf := make([]byte, size)
	if _, err := io.ReadFull(r, buf); err != nil {
		return "", err
	}

	// Discard any alignment padding to 8-byte boundary
	pad := (8 - (size % 8)) % 8
	if pad > 0 {
		if _, err := io.CopyN(io.Discard, r, int64(pad)); err != nil {
			return "", err
		}
	}

	return string(buf), nil
}
