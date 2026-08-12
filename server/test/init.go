package test

import (
	"github.com/rs/zerolog"
	"momenttally.com/server/logger"
)

func init() {
	logger.Init(zerolog.WarnLevel)
}
