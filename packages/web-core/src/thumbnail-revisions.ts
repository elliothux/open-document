/** Keep previews across edits whose affected regions are known. */
export class ThumbnailRevisions {
  private revision = -1;
  private baseline = -1;
  private readonly regions = new Map<string, number>();

  update(before: number, after: number, affected: Iterable<string>): void {
    if (before === after) return;
    if (this.revision !== before) {
      this.regions.clear();
      this.baseline = before;
    }
    this.revision = after;
    for (const id of affected) this.regions.set(id, after);
  }

  version(id: string, revision: number): number {
    return revision === this.revision
      ? (this.regions.get(id) ?? this.baseline)
      : revision;
  }
}
