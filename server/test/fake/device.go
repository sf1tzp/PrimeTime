package fake

import (
	"context"

	"momenttally.com/server/auth"
	"momenttally.com/server/model"
)

// Device creates a context with a fake device.
func Device(device *model.Device) context.Context {
	return auth.WithDevice(context.Background(), device)
}
