export function greet(name: string): string {
  return `Hello, ${name}!`;
}

export function shout(name: string): string {
  // Exists so the template's own PR has a changed, covered line for diff-cover.
  return greet(name).toUpperCase();
}
