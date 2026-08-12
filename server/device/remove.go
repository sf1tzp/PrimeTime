package device

import (
	"context"
	"fmt"

	"github.com/jinzhu/copier"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
)

// RemoveDevice removes a device
func (r *ResolverForDevice) RemoveDevice(ctx context.Context, id int) (*gqlmodel.Device, error) {
	device := model.Device{ID: id}
	if r.DB.Where(&model.Device{UserID: auth.GetUser(ctx).ID}).Find(&device).RecordNotFound() {
		return nil, fmt.Errorf("device not found")
	}

	remove := r.DB.Delete(&device)
	gqlDevice := &gqlmodel.Device{}
	copier.Copy(gqlDevice, &device)
	return gqlDevice, remove.Error
}
