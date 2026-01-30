export function buildPagination(page?: number, pageSize = 20) {
  const safePage = page && page > 0 ? page : 1;
  const take = pageSize;
  const skip = (safePage - 1) * take;
  return { take, skip, page: safePage };
}
