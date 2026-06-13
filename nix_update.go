package main

import (
	"bytes"
	"debug/elf"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

type SourceConfig struct {
	Sources     map[string]string         `json:"sources"`
	Entrypoints map[string]EntrypointSpec `json:"entrypoints"`
}

type EntrypointSpec struct {
	Source    string `json:"source"`
	Attribute string `json:"attribute"`
	Binary    string `json:"binary"`
}

type Lockfile struct {
	Channel          string                     `json:"channel"`
	ResolvedPackages map[string]ResolvedPackage `json:"resolved_packages"`
	Entrypoints      map[string]LockEntrypoint  `json:"entrypoints"`
}

type ResolvedPackage struct {
	PkgName   string `json:"pkg_name"`
	StoreName string `json:"store_name"`
}

type LockEntrypoint struct {
	PackageHash       string        `json:"package_hash"`
	BinaryPath        string        `json:"binary_path"`
	LinkerPackageHash string        `json:"linker_package_hash"`
	LinkerPath        string        `json:"linker_path"`
	LibFiles          []LibraryFile `json:"lib_files"`
	AdditionalLibs    []string      `json:"additional_libs"`
}

type LibraryFile struct {
	PackageHash string `json:"package_hash"`
	FilePath    string `json:"file_path"`
}

var usePortable = false
var physicalStorePath = ""
const portableBin = "./nix-portable"

func initNix() {
	_, err := exec.LookPath("nix-build")
	if err == nil {
		fmt.Println("Found native Nix on host. Using native commands.")
		return
	}

	// Native Nix not found. Must use nix-portable on Linux.
	if runtime.GOOS != "linux" {
		fmt.Println("Error: Native Nix not found. On macOS, please install Nix or run this updater inside a Linux container/VM.")
		os.Exit(1)
	}

	usePortable = true

	npLocation := os.Getenv("NP_LOCATION")
	if npLocation == "" {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			fmt.Printf("Error getting user home dir: %v\n", err)
			os.Exit(1)
		}
		physicalStorePath = filepath.Join(homeDir, ".nix-portable", "nix", "store")
	} else {
		physicalStorePath = filepath.Join(npLocation, "nix", "store")
	}
	fmt.Printf("Using nix-portable. Physical store mapped to: %s\n", physicalStorePath)

	if _, err := os.Stat(portableBin); os.IsNotExist(err) {
		fmt.Println("Native Nix not found. Bootstrapping nix-portable...")
		arch := runtime.GOARCH
		var nixArch string
		if arch == "amd64" {
			nixArch = "x86_64"
		} else if arch == "arm64" {
			nixArch = "aarch64"
		} else {
			fmt.Printf("Error: Unsupported architecture for nix-portable: %s\n", arch)
			os.Exit(1)
		}

		downloadURL := fmt.Sprintf("https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-%s", nixArch)
		fmt.Printf("Downloading nix-portable from %s...\n", downloadURL)

		resp, err := http.Get(downloadURL)
		if err != nil {
			fmt.Printf("Error downloading nix-portable: %v\n", err)
			os.Exit(1)
		}
		defer resp.Body.Close()

		out, err := os.OpenFile(portableBin, os.O_CREATE|os.O_WRONLY, 0755)
		if err != nil {
			fmt.Printf("Error creating file %s: %v\n", portableBin, err)
			os.Exit(1)
		}
		defer out.Close()

		_, err = io.Copy(out, resp.Body)
		if err != nil {
			fmt.Printf("Error saving nix-portable: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("nix-portable bootstrapped successfully.")
	}
}

func runNixCmd(subcommand string, args ...string) ([]byte, error) {
	var cmd *exec.Cmd
	if usePortable {
		fullArgs := append([]string{subcommand}, args...)
		cmd = exec.Command(portableBin, fullArgs...)
	} else {
		cmd = exec.Command(subcommand, args...)
	}

	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return nil, fmt.Errorf("command failed: %v\nStderr: %s", err, stderr.String())
	}
	return out.Bytes(), nil
}

func readStoreFile(path string) ([]byte, error) {
	if usePortable && strings.HasPrefix(path, "/nix/store/") {
		rel := strings.TrimPrefix(path, "/nix/store/")
		path = filepath.Join(physicalStorePath, rel)
	}
	return os.ReadFile(path)
}

func listStoreFiles(logicalPath string) ([]string, error) {
	physicalPath := logicalPath
	if usePortable && strings.HasPrefix(logicalPath, "/nix/store/") {
		rel := strings.TrimPrefix(logicalPath, "/nix/store/")
		physicalPath = filepath.Join(physicalStorePath, rel)
	}

	var files []string
	err := filepath.Walk(physicalPath, func(filePath string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			logicalFilePath := filePath
			if usePortable && strings.HasPrefix(filePath, physicalStorePath) {
				rel := strings.TrimPrefix(filePath, physicalStorePath)
				logicalFilePath = "/nix/store" + rel
			}
			files = append(files, logicalFilePath)
		}
		return nil
	})
	return files, err
}

func main() {
	fmt.Println("=== Nix Dependency Updater ===")

	initNix()

	// 1. Read nix_deps.json
	configBytes, err := os.ReadFile("nix_deps.json")
	if err != nil {
		fmt.Printf("Error reading nix_deps.json: %v\n", err)
		os.Exit(1)
	}

	var config SourceConfig
	if err := json.Unmarshal(configBytes, &config); err != nil {
		fmt.Printf("Error parsing nix_deps.json: %v\n", err)
		os.Exit(1)
	}

	lockfile := Lockfile{
		Channel:          "nix-resolved",
		ResolvedPackages: make(map[string]ResolvedPackage),
		Entrypoints:      make(map[string]LockEntrypoint),
	}

	// Cache to avoid scanning the same store path multiple times
	packageFilesCache := make(map[string]map[string]string)

	for entryName, spec := range config.Entrypoints {
		fmt.Printf("\nResolving entrypoint: %s (Attr: %s, Source: %s)\n", entryName, spec.Attribute, spec.Source)

		tarballURL, ok := config.Sources[spec.Source]
		if !ok {
			fmt.Printf("Error: source '%s' not found in config\n", spec.Source)
			os.Exit(1)
		}

		// 2. Build and download the package using nix-build
		expr := fmt.Sprintf("with import (fetchTarball \"%s\") {}; %s", tarballURL, spec.Attribute)
		fmt.Printf("Building and realising Nix expression (downloading if cached)...\n")
		out, err := runNixCmd("nix-build", "--no-out-link", "-E", expr)
		if err != nil {
			fmt.Printf("nix-build failed: %v\n", err)
			os.Exit(1)
		}

		var storePath string
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "/nix/store/") {
				storePath = line
				break
			}
		}
		if storePath == "" {
			fmt.Printf("Error: nix-build did not output a valid store path. Output:\n%s\n", string(out))
			os.Exit(1)
		}
		fmt.Printf("Resolved and realised store path: %s\n", storePath)

		// 3. Query transitive closure of references using nix-store
		fmt.Printf("Querying transitive closure...\n")
		outQuery, err := runNixCmd("nix-store", "-qR", storePath)
		if err != nil {
			fmt.Printf("nix-store -qR failed: %v\n", err)
			os.Exit(1)
		}

		var closurePaths []string
		for _, line := range strings.Split(string(outQuery), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "/nix/store/") {
				closurePaths = append(closurePaths, line)
			}
		}
		closurePaths = append(closurePaths, storePath)

		// De-duplicate closure paths
		uniqueClosure := make(map[string]string)
		for _, path := range closurePaths {
			path = strings.TrimSpace(path)
			if path == "" {
				continue
			}
			basename := filepath.Base(path)
			if len(basename) < 32 {
				continue
			}
			hash := basename[:32]
			uniqueClosure[hash] = path
		}

		var entrypointPackageHash string
		var linkerPackageHash string
		var linkerPath string
		var additionalLibs []string

		// Add packages to resolved packages list and build file cache
		for hash, path := range uniqueClosure {
			basename := filepath.Base(path)
			pkgName := basename[33:] // strip hash and hyphen

			// If it's the target package
			if path == storePath {
				entrypointPackageHash = hash
			}

			lockfile.ResolvedPackages[hash] = ResolvedPackage{
				PkgName:   pkgName,
				StoreName: basename,
			}
			additionalLibs = append(additionalLibs, hash)

			// Index files for this package if not already cached
			if _, cached := packageFilesCache[hash]; !cached {
				files := make(map[string]string)
				pathList, err := listStoreFiles(path)
				if err == nil {
					for _, filePath := range pathList {
						relPath := strings.TrimPrefix(filePath, path+"/")
						files[relPath] = filePath
						// Also index just by base name for easy lookups
						files[filepath.Base(filePath)] = relPath
					}
					packageFilesCache[hash] = files
				}
			}
		}

		// 4. Find dynamic linker in closure
		for hash, path := range uniqueClosure {
			basename := filepath.Base(path)
			if strings.Contains(basename, "glibc-") {
				files := packageFilesCache[hash]
				// Look for ld-linux interpreter
				for relPath := range files {
					if (strings.HasPrefix(relPath, "lib/ld-linux-") && strings.Contains(relPath, ".so.")) ||
						(strings.HasPrefix(relPath, "lib/ld-") && strings.Contains(relPath, ".so.")) {
						linkerPackageHash = hash
						linkerPath = relPath
						break
					}
				}
				if linkerPath != "" {
					break
				}
			}
		}

		// Fallback search
		if linkerPath == "" {
			for hash := range uniqueClosure {
				files := packageFilesCache[hash]
				for relPath := range files {
					if strings.Contains(relPath, "ld-linux") || strings.Contains(relPath, "ld-2") {
						linkerPackageHash = hash
						linkerPath = relPath
						break
					}
				}
				if linkerPath != "" {
					break
				}
			}
		}

		fmt.Printf("Selected linker: @nix_pkg_%s//:%s\n", linkerPackageHash, linkerPath)

		// 5. Parse ELF binary to find needed libraries
		binaryFullPath := filepath.Join(storePath, spec.Binary)
		binBytes, err := readStoreFile(binaryFullPath)
		if err != nil {
			fmt.Printf("Warning: could not read binary file %s: %v\n", binaryFullPath, err)
			continue
		}

		f, err := elf.NewFile(bytes.NewReader(binBytes))
		if err != nil {
			fmt.Printf("Warning: could not parse ELF headers for %s: %v\n", binaryFullPath, err)
			continue
		}

		libs, err := f.ImportedLibraries()
		if err != nil {
			fmt.Printf("Warning: could not get imported libraries: %v\n", err)
			continue
		}

		fmt.Printf("Imported libraries: %v\n", libs)

		var libFiles []LibraryFile
		for _, lib := range libs {
			// Skip system/compiler libraries resolved by default glibc loader
			if strings.HasPrefix(lib, "libc.so") ||
				strings.HasPrefix(lib, "libm.so") ||
				strings.HasPrefix(lib, "libdl.so") ||
				strings.HasPrefix(lib, "librt.so") ||
				strings.HasPrefix(lib, "libpthread.so") ||
				strings.HasPrefix(lib, "ld-linux") ||
				strings.HasPrefix(lib, "libresolv.so") ||
				strings.HasPrefix(lib, "libutil.so") {
				continue
			}

			// Search for this library in closure packages
			found := false
			for hash := range uniqueClosure {
				if hash == linkerPackageHash {
					continue
				}
				files := packageFilesCache[hash]
				if relPath, ok := files[lib]; ok {
					libFiles = append(libFiles, LibraryFile{
						PackageHash: hash,
						FilePath:    relPath,
					})
					fmt.Printf("  Resolved library %s -> @nix_pkg_%s//:%s\n", lib, hash, relPath)
					found = true
					break
				}
			}
			if !found {
				fmt.Printf("  Warning: could not resolve library %s in closure\n", lib)
			}
		}

		lockfile.Entrypoints[entryName] = LockEntrypoint{
			PackageHash:       entrypointPackageHash,
			BinaryPath:        spec.Binary,
			LinkerPackageHash: linkerPackageHash,
			LinkerPath:        linkerPath,
			LibFiles:          libFiles,
			AdditionalLibs:    additionalLibs,
		}
	}

	// 6. Write nix_lock.json
	lockBytes, err := json.MarshalIndent(lockfile, "", "  ")
	if err != nil {
		fmt.Printf("Error marshaling lockfile: %v\n", err)
		os.Exit(1)
	}

	if err := os.WriteFile("nix_lock.json", lockBytes, 0644); err != nil {
		fmt.Printf("Error writing nix_lock.json: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("\n=== Lockfile generated successfully! nix_lock.json has been updated. ===")
}
