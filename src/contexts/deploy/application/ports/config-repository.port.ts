export interface ConfigRepositoryPort {
  readCurrentApp(): Promise<string | null>;
}
