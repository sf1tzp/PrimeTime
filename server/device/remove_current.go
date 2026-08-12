package device

import (
	"context"

	"github.com/jinzhu/copier"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
)

// RemoveCurrentDevice removes the current authenticated device
func (r *ResolverForDevice) RemoveCurrentDevice(ctx context.Context) (*gqlmodel.Device, error) {
	device := auth.GetDevice(ctx)
	remove := r.DB.Delete(device)
	gqlDevice := &gqlmodel.Device{}
	copier.Copy(gqlDevice, device)
	return gqlDevice, remove.Error
}
