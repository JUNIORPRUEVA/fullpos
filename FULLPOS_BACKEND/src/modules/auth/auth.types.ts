export interface JwtUser {
  id: number;
  companyId: number;
  username: string;
  role: string;
  email?: string | null;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}
