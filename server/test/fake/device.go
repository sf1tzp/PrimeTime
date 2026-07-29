package fake

import (
	"context"

	"primetime.tools/server/auth"
	"primetime.tools/server/model"
)

// Device creates a context with a fake device.
func Device(device *model.Device) context.Context {
	return auth.WithDevice(context.Background(), device)
}
