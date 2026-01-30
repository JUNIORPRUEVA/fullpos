import { Router } from 'express';
import { authGuard } from '../../middlewares/authGuard';
import { overrideKeyGuard } from '../../middlewares/overrideKeyGuard';
import { validate } from '../../middlewares/validate';
import {
  loginSchema,
  provisionOwnerSchema,
  provisionUserSchema,
  refreshSchema,
} from './auth.validation';
import {
  getProfile,
  login,
  provisionAdminUser,
  provisionOwnerByRnc,
  refresh,
} from './auth.service';

const router = Router();

router.post('/login', validate(loginSchema), async (req, res, next) => {
  try {
    const { identifier, password } = req.body;
    const result = await login(identifier, password);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/refresh', validate(refreshSchema), async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    const result = await refresh(refreshToken);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.get('/me', authGuard, async (req, res, next) => {
  try {
    const profile = await getProfile(req.user!.id);
    res.json(profile);
  } catch (err) {
    next(err);
  }
});

// Aprovisiona/actualiza el usuario owner por RNC.
// Se protege con OVERRIDE_API_KEY si está configurada (x-override-key o x-cloud-key).
router.post('/provision-owner', overrideKeyGuard, validate(provisionOwnerSchema), async (req, res, next) => {
  try {
    const { companyRnc, companyCloudId, companyName, username, password } = req.body;
    const result = await provisionOwnerByRnc(
      companyRnc,
      username,
      password,
      companyName,
      companyCloudId,
    );
    res.json(result);
  } catch (err) {
    next(err);
  }
});

// Aprovisiona/actualiza usuarios admin para Owner (por RNC o ID interno).
router.post('/provision-user', overrideKeyGuard, validate(provisionUserSchema), async (req, res, next) => {
  try {
    const { companyRnc, companyCloudId, companyName, username, password } = req.body;
    const result = await provisionAdminUser({
      companyRnc,
      companyCloudId,
      companyName,
      username,
      password,
    });
    res.json(result);
  } catch (err) {
    next(err);
  }
});

export default router;
