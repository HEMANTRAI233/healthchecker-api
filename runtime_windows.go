//go:build windows

package main

import (
	"context"
	"errors"

	"golang.org/x/sys/windows/svc"
	"healthchecker-api/internal/app"
)

const serviceName = "HealthCheckerAPI"

func run() error {
	isService, err := svc.IsWindowsService()
	if err != nil {
		return err
	}
	if !isService {
		return runInteractive()
	}
	return svc.Run(serviceName, &serviceRunner{})
}

type serviceRunner struct{}

func (s *serviceRunner) Execute(_ []string, r <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	const accepted = svc.AcceptStop | svc.AcceptShutdown

	status <- svc.Status{State: svc.StartPending}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errCh := make(chan error, 1)
	go func() {
		errCh <- app.Run(ctx, migrationFiles)
	}()

	status <- svc.Status{State: svc.Running, Accepts: accepted}

	for {
		select {
		case req := <-r:
			switch req.Cmd {
			case svc.Interrogate:
				status <- req.CurrentStatus
			case svc.Stop, svc.Shutdown:
				status <- svc.Status{State: svc.StopPending}
				cancel()
				err := <-errCh
				if err != nil && !errors.Is(err, context.Canceled) {
					return false, 1
				}
				status <- svc.Status{State: svc.Stopped}
				return false, 0
			}
		case err := <-errCh:
			if err != nil && !errors.Is(err, context.Canceled) {
				return false, 1
			}
			status <- svc.Status{State: svc.Stopped}
			return false, 0
		}
	}
}
