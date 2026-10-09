package cache

import (
	"context"
	"time"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const defaultTTL = 5 * time.Minute

func NewRedisClient(redisURL string) (*redis.Client, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		logger.L().Error("failed to parse Redis URL", zap.Error(err))
		return nil, err
	}

	rdb := redis.NewClient(opts)
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		logger.L().Error("failed to connect to Redis", zap.Error(err))
		return nil, err
	}

	return rdb, nil
}
