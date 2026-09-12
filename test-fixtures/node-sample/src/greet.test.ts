import { describe, it, expect } from 'vitest';
import { greet, shout } from './greet';

describe('greet', () => {
  it('greets by name', () => {
    expect(greet('world')).toBe('Hello, world!');
  });

  it('shouts', () => {
    expect(shout('world')).toBe('HELLO, WORLD!');
  });
});
