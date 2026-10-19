// Reuse the same real host/capture/feedback/score harness with the non-device content plan.
process.env.DRYRUN_PRACTICE_NONDEVICE='1';
await import('./practice-phases-eval.js');
