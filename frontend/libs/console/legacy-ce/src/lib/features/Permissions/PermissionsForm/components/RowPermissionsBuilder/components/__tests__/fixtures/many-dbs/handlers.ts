import { rest } from 'msw';
import export_metadata from './export_metadata';
import get_table_info from './get_table_info';
import { introspection } from './introspection';

export function handlers() {
  return [
    rest.post('http://localhost:8080/v1/graphql', async (req, res, ctx) => {
      return res(ctx.json(introspection));
    }),
    rest.post('http://localhost:8080/v1/metadata', async (req, res, ctx) => {
      const body = await req.json();
      if (body.type === 'export_metadata') {
        return res(ctx.json(export_metadata));
      }
      if (body.type === 'get_table_info') {
        return res(ctx.json(get_table_info));
      }
      return res(ctx.json({}));
    }),
  ];
}
