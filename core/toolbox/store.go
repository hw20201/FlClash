package toolbox

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Day files are plain JSON. BettBox's store hides the same payload behind an
// obfuscated gob format; FlowCat keeps the bytes readable instead.
func encodeStore(value any) ([]byte, error) {
	return json.Marshal(value)
}

func writeStoreBytes(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	temp := path + ".tmp"
	if err := os.WriteFile(temp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(temp, path)
}

func writeStoreFile(path string, value any) error {
	data, err := encodeStore(value)
	if err != nil {
		return err
	}
	return writeStoreBytes(path, data)
}

func readStoreFile(path string, value any) bool {
	content, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return json.Unmarshal(content, value) == nil
}
