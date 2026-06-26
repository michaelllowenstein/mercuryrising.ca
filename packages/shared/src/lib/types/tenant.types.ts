// // tenant.types.ts — Onboarded shared TypeScript interfaces
// // Imported by: portal (at build time via TENANT_DOMAIN constant)
// //              api (at startup via domain_loader.py-generated dicts)
// //              admin-cli (for typed API client request/response models)

// export interface RepoConfig {
//   env: string;
//   default: string;
// }

// export interface Operation {
//   label: string;
//   controllers: string[];
//   services: string[];
//   queues: string[];
//   js: string[];
// }

// export interface GlossaryEntry {
//   label: string;
//   definition: string;
//   see_also: string[];
// }

// export interface ScanRule {
//   label: string;
//   pattern: string;
//   severity: 'critical' | 'error' | 'warning' | 'info';
//   category: 'security' | 'convention' | 'architecture' | 'dependency' | 'observability';
//   scope: string[];
//   repos: string[];
//   exclude: string[];
//   reference: string;
//   fix_hint: string;
// }

// export interface IslandProps {
//   tenantSlug: string;
//   apiBaseUrl: string;
//   onNavigate?: (route: string) => void;
// }

// export interface TenantDomain {
//   version: string;
//   tenant: {
//     slug: string;
//     brand_name: string;
//     cli_name: string;
//     terminology: {
//       operations: string;
//       statuses: string;
//       products: string;
//       queues?: string;
//       portals?: string;
//     };
//   };
//   config: {
//     repos: Record<string, RepoConfig>;
//   };
//   operations: Record<string, Operation>;
//   statuses: Record<string, string>;
//   products: Record<string, unknown>;
//   portals: Record<string, unknown>;
//   queues: Record<string, unknown>;
//   glossary: Record<string, GlossaryEntry>;
//   scan_rules: Record<string, ScanRule>;
// }