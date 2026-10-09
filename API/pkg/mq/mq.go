package mq

import (
	"fmt"
	amqp "github.com/rabbitmq/amqp091-go"
)

type ExchangeConfig struct {
	Name       string
	Kind       string
	Durable    bool
	AutoDelete bool
	Internal   bool
	NoWait     bool
	Args       amqp.Table
}

type Client struct {
	Conn    *amqp.Connection
	Channel *amqp.Channel

	declared map[string]bool
}

func NewClient(amqpURL string) (*Client, error) {
	conn, err := amqp.Dial(amqpURL)
	if err != nil {
		return nil, fmt.Errorf("dialing amqp: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("opening channel: %w", err)
	}

	return &Client{
		Conn:     conn,
		Channel:  ch,
		declared: make(map[string]bool),
	}, nil
}

func (c *Client) DeclareExchange(cfg ExchangeConfig) error {
	if c.declared[cfg.Name] {
		return nil
	}
	if err := c.Channel.ExchangeDeclare(
		cfg.Name, cfg.Kind,
		cfg.Durable, cfg.AutoDelete,
		cfg.Internal, cfg.NoWait,
		cfg.Args,
	); err != nil {
		return fmt.Errorf("declare exchange %q: %w", cfg.Name, err)
	}
	c.declared[cfg.Name] = true
	return nil
}

func (c *Client) Close() error {
	c.Channel.Close()
	return c.Conn.Close()
}
