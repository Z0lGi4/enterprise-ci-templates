import { describe, it, expect } from 'vitest';
import { greet } from './greet';

describe('greet', () => {
  it('greets by name', () => {
    expect(greet('world')).toBe('Hello, world!');
  });
});
