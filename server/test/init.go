package test

import (
	"github.com/rs/zerolog"
	"primetime.tools/server/logger"
)

func init() {
	logger.Init(zerolog.WarnLevel)
}
