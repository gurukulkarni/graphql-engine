module Hasura.LogicalModel.Common
  ( toFieldInfo,
    columnsFromFields,
    logicalModelFieldsToFieldInfo,
    getSelPermInfoForLogicalModel,
  )
where

import Data.Bifunctor (bimap)
import Data.HashMap.Strict qualified as HashMap
import Data.HashMap.Strict.InsOrd qualified as InsOrdHashMap
import Data.Text.Extended (ToTxt (toTxt))
import Hasura.LogicalModel.Cache
import Hasura.LogicalModel.NullableScalarType (NullableScalarType (..))
import Hasura.LogicalModel.Types (LogicalModelField (..), LogicalModelType (..), LogicalModelTypeScalar (..))
import Hasura.Prelude
import Hasura.RQL.IR.BoolExp (AnnRedactionExp (..), gBoolExpTrue)
import Hasura.RQL.Types.Backend (Backend (..))
import Hasura.RQL.Types.Column (ColumnInfo (..), ColumnMutability (..), ColumnType (..), StructuredColumnInfo (..), fromCol)
import Hasura.RQL.Types.Permission (AllowedRootFields (..))
import Hasura.RQL.Types.Roles (RoleName, adminRoleName)
import Hasura.Table.Cache (FieldInfo (..), FieldInfoMap, RolePermInfo (..), SelPermInfo (..))
import Language.GraphQL.Draft.Syntax qualified as G

columnsFromFields ::
  InsOrdHashMap.InsOrdHashMap k (LogicalModelField b) ->
  InsOrdHashMap.InsOrdHashMap k (NullableScalarType b)
columnsFromFields =
  InsOrdHashMap.mapMaybe
    ( \case
        LogicalModelField
          { lmfType =
              LogicalModelTypeScalar
                ( LogicalModelTypeScalarC
                    { lmtsScalar = nstType,
                      lmtsNullable = nstNullable
                    }
                  ),
            lmfDescription = nstDescription
          } ->
            Just (NullableScalarType {..})
        _ -> Nothing
    )

toFieldInfo :: forall b. (Backend b) => InsOrdHashMap.InsOrdHashMap (Column b) (NullableScalarType b) -> Maybe [FieldInfo b]
toFieldInfo fields =
  traverseWithIndex
    (\i -> fmap FIColumn . logicalModelToColumnInfo i)
    (InsOrdHashMap.toList fields)

traverseWithIndex :: (Applicative m) => (Int -> aa -> m bb) -> [aa] -> m [bb]
traverseWithIndex f = zipWithM f [0 ..]

logicalModelToColumnInfo :: forall b. (Backend b) => Int -> (Column b, NullableScalarType b) -> Maybe (StructuredColumnInfo b)
logicalModelToColumnInfo i (column, NullableScalarType {..}) = do
  name <- G.mkName (toTxt column)
  pure
    $
    -- TODO(dmoverton): handle object and array columns
    SCIScalarColumn
    $ ColumnInfo
      { ciColumn = column,
        ciName = name,
        ciPosition = i,
        ciType = ColumnScalar nstType,
        ciIsNullable = nstNullable,
        ciDescription = G.Description <$> nstDescription,
        ciMutability = ColumnMutability {_cmIsInsertable = False, _cmIsUpdatable = False}
      }

logicalModelFieldsToFieldInfo ::
  forall b.
  (Backend b) =>
  InsOrdHashMap.InsOrdHashMap (Column b) (LogicalModelField b) ->
  FieldInfoMap (FieldInfo b)
logicalModelFieldsToFieldInfo =
  HashMap.fromList
    . fmap (bimap (fromCol @b) FIColumn)
    . fromMaybe mempty
    . traverseWithIndex
      (\i (column, lmf) -> (,) column <$> logicalModelToColumnInfo i (column, lmf))
    . InsOrdHashMap.toList
    . columnsFromFields

getSelPermInfoForLogicalModel ::
  (Backend b) =>
  RoleName ->
  LogicalModelInfo b ->
  Maybe (SelPermInfo b)
getSelPermInfoForLogicalModel role logicalModel =
  if role == adminRoleName
    then Just $ mkAdminSelPermInfo logicalModel
    else HashMap.lookup role (_lmiPermissions logicalModel) >>= _permSel

mkAdminSelPermInfo :: (Backend b) => LogicalModelInfo b -> SelPermInfo b
mkAdminSelPermInfo LogicalModelInfo {..} =
  SelPermInfo
    { spiCols = HashMap.fromList $ (,NoRedaction) <$> InsOrdHashMap.keys _lmiFields,
      spiComputedFields = mempty,
      spiFilter = gBoolExpTrue,
      spiLimit = Nothing,
      spiAllowAgg = True,
      spiRequiredHeaders = mempty,
      spiAllowedQueryRootFields = ARFAllowAllRootFields,
      spiAllowedSubscriptionRootFields = ARFAllowAllRootFields
    }
