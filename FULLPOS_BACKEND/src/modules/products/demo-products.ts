import { Prisma } from '@prisma/client';

const baseProducts = [
  {
    name: 'Taladro inalámbrico 20V',
    description: 'Incluye batería y cargador rápido',
    price: 3200,
    stock: 12,
    imageUrl:
      'https://images.unsplash.com/photo-1507721999472-8ed4421c4af2?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Martillo de fibra 16oz',
    description: 'Mango ergonómico antideslizante',
    price: 750,
    stock: 30,
    imageUrl:
      'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Juego destornilladores 6pzs',
    description: 'Punta plana y philips, puntas imantadas',
    price: 950,
    stock: 20,
    imageUrl:
      'https://images.unsplash.com/photo-1523419400524-fc1e0d787ab7?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Llave ajustable 12"',
    description: 'Acero forjado, escala métrica',
    price: 680,
    stock: 18,
    imageUrl:
      'https://images.unsplash.com/photo-1523419400524-fc1e0d787ab7?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Cinta métrica 8m',
    description: 'Con freno y clip metálico',
    price: 420,
    stock: 40,
    imageUrl:
      'https://images.unsplash.com/photo-1503389152951-9f343605f61e?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Serrucho profesional 20"',
    description: 'Dientes templados para corte rápido',
    price: 560,
    stock: 22,
    imageUrl:
      'https://images.unsplash.com/photo-1454990926518-22f1f008b4e0?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Nivel de aluminio 60cm',
    description: 'Tres burbujas, precisión 0.5mm/m',
    price: 390,
    stock: 28,
    imageUrl:
      'https://images.unsplash.com/photo-1503389152951-9f343605f61e?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Guantes de trabajo cuero',
    description: 'Refuerzo en palma y dedos',
    price: 250,
    stock: 45,
    imageUrl:
      'https://images.unsplash.com/photo-1514996937319-344454492b37?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Manguera de aire 10m',
    description: '1/4" reforzada para compresor',
    price: 720,
    stock: 16,
    imageUrl:
      'https://images.unsplash.com/photo-1503389152951-9f343605f61e?auto=format&fit=crop&w=800&q=80',
  },
  {
    name: 'Caja de herramientas 19"',
    description: 'Con bandeja interna y cierres metálicos',
    price: 1150,
    stock: 14,
    imageUrl:
      'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=800&q=80',
  },
];

export function buildDemoProducts(companyId: number, total = 50): Prisma.ProductCreateManyInput[] {
  const items: Prisma.ProductCreateManyInput[] = [];
  for (let i = 0; i < total; i++) {
    const base = baseProducts[i % baseProducts.length];
    const idx = i + 1;
    items.push({
      companyId,
      code: `DEMO-${idx.toString().padStart(3, '0')}`,
      name: base.name,
      description: base.description,
      price: base.price,
      stock: base.stock,
      imageUrl: base.imageUrl,
      isDemo: true,
    });
  }
  return items;
}
