module Test.Auth.Authorization.InheritedRoles.ColumnRedactionSpec
  ( spec,
  )
where

import Data.Aeson (Value (String), object, (.=))
import Data.List.NonEmpty qualified as NE
import Data.String.Interpolate (i)
import Harness.Backend.Postgres qualified as Postgres
import Harness.GraphqlEngine qualified as GraphqlEngine
import Harness.Permissions (InheritedRoleDetails (..), Permission (..), SelectPermissionDetails (..), selectPermission)
import Harness.Quoter.Graphql
import Harness.Quoter.Yaml (interpolateYaml, yaml)
import Harness.Schema (Table (..), table)
import Harness.Schema qualified as Schema
import Harness.Test.Fixture qualified as Fixture
import Harness.Test.SetupAction (setupPermissionsAction)
import Harness.TestEnvironment (GlobalTestEnvironment, TestEnvironment, getBackendTypeConfig)
import Harness.Yaml (shouldReturnYaml)
import Hasura.Prelude
import Test.Hspec (SpecWith, describe, it)

--------------------------------------------------------------------------------
-- Preamble

spec :: SpecWith GlobalTestEnvironment
spec =
  Fixture.run
    ( NE.fromList
        [ (Fixture.fixture $ Fixture.Backend Postgres.backendTypeMetadata)
            { Fixture.setupTeardown = \(testEnv, _) ->
                Postgres.setupTablesAction schema testEnv
                  : computedFieldSetupActions testEnv
                    <> [setupPermissionsAction permissions testEnv]
            }
        ]
    )
    tests

--------------------------------------------------------------------------------
-- Schema

schema :: [Schema.Table]
schema = [manager, employee]

manager :: Schema.Table
manager =
  (table "manager")
    { tableColumns =
        [ Schema.column "id" Schema.TInt,
          Schema.column "first_name" Schema.TStr,
          Schema.column "last_name" Schema.TStr
        ],
      tablePrimaryKey = ["id"],
      tableData =
        [ [Schema.VInt 1, Schema.VStr "Ryan", Schema.VStr "Ray"],
          [Schema.VInt 2, Schema.VStr "Martin", Schema.VStr "Graham"],
          [Schema.VInt 3, Schema.VStr "Althea", Schema.VStr "Weiss"],
          [Schema.VInt 4, Schema.VStr "Bec", Schema.VStr "Vo"]
        ]
    }

employee :: Schema.Table
employee =
  (table "employee")
    { tableColumns =
        [ Schema.column "id" Schema.TInt,
          Schema.column "first_name" Schema.TStr,
          Schema.column "last_name" Schema.TStr,
          Schema.column "nationality" Schema.TStr,
          Schema.column "monthly_salary" Schema.TInt,
          Schema.column "engineering_manager_id" Schema.TInt,
          Schema.column "hr_manager_id" Schema.TInt
        ],
      tablePrimaryKey = ["id"],
      tableReferences =
        [ Schema.reference "engineering_manager_id" "manager" "id",
          Schema.reference "hr_manager_id" "manager" "id"
        ],
      tableData =
        [ [Schema.VInt 1, Schema.VStr "David", Schema.VStr "Holden", Schema.VStr "Australian", Schema.VInt 5000, Schema.VInt 1, Schema.VInt 3],
          [Schema.VInt 2, Schema.VStr "Grant", Schema.VStr "Smith", Schema.VStr "Australian", Schema.VInt 6000, Schema.VInt 1, Schema.VInt 4],
          [Schema.VInt 3, Schema.VStr "Xin", Schema.VStr "Cheng", Schema.VStr "Chinese", Schema.VInt 5500, Schema.VInt 2, Schema.VInt 3],
          [Schema.VInt 4, Schema.VStr "Sarah", Schema.VStr "Smith", Schema.VStr "British", Schema.VInt 4000, Schema.VInt 2, Schema.VInt 4]
        ]
    }

computedFieldSetupActions :: TestEnvironment -> [Fixture.SetupAction]
computedFieldSetupActions testEnv =
  let schemaName = Schema.getSchemaName testEnv
      backendTypeMetadata = fromMaybe (error "Unknown backend") $ getBackendTypeConfig testEnv
      source = Fixture.backendSourceName backendTypeMetadata
   in [ Fixture.SetupAction
          { Fixture.setupAction =
              Postgres.run_ testEnv
                $ [i|
                  CREATE FUNCTION #{ employee_yearly_salary schemaName }(employee_row employee)
                  RETURNS integer AS $$
                    SELECT employee_row.monthly_salary * 12
                  $$ LANGUAGE sql STABLE;
                |],
            Fixture.teardownAction = \_ -> pure ()
          },
        Fixture.SetupAction
          { Fixture.setupAction =
              Schema.trackComputedField
                source
                employee
                "employee_yearly_salary"
                "yearly_salary"
                [yaml| null |]
                [yaml| null |]
                testEnv,
            Fixture.teardownAction = \_ -> pure ()
          }
      ]

employee_yearly_salary :: Schema.SchemaName -> Text
employee_yearly_salary (Schema.SchemaName name) = name <> ".employee_yearly_salary"

--------------------------------------------------------------------------------
-- Permissions

permissions :: [Permission]
permissions =
  [ SelectPermission
      selectPermission
        { selectPermissionTable = "employee",
          selectPermissionRole = "employee_public_info",
          selectPermissionColumns = ["id", "first_name", "last_name"],
          selectPermissionAllowAggregations = True,
          selectPermissionRows = object []
        },
    SelectPermission
      selectPermission
        { selectPermissionTable = "employee",
          selectPermissionRole = "employee_private_info",
          selectPermissionColumns = ["id", "first_name", "last_name", "monthly_salary"],
          selectPermissionComputedFields = ["yearly_salary"],
          selectPermissionAllowAggregations = True,
          selectPermissionRows =
            object
              [ "id" .= String "X-Hasura-Employee-Id"
              ]
        },
    InheritedRole
      InheritedRoleDetails
        { inheritedRoleName = "employee",
          inheritedRoleRoleSet = ["employee_public_info", "employee_private_info"]
        },
    SelectPermission
      selectPermission
        { selectPermissionTable = "manager",
          selectPermissionRole = "all_managers",
          selectPermissionColumns = ["id", "first_name", "last_name"],
          selectPermissionAllowAggregations = True,
          selectPermissionRows = object []
        },
    SelectPermission
      selectPermission
        { selectPermissionTable = "employee",
          selectPermissionRole = "all_managers",
          selectPermissionColumns = ["id", "first_name", "last_name", "engineering_manager_id", "hr_manager_id"],
          selectPermissionAllowAggregations = True,
          selectPermissionRows = object []
        },
    SelectPermission
      selectPermission
        { selectPermissionTable = "employee",
          selectPermissionRole = "manager_employee_private_info",
          selectPermissionColumns = ["id", "first_name", "last_name", "nationality", "monthly_salary", "engineering_manager_id", "hr_manager_id"],
          selectPermissionComputedFields = ["yearly_salary"],
          selectPermissionAllowAggregations = True,
          selectPermissionRows =
            object
              [ "hr_manager_id" .= String "X-Hasura-Manager-Id"
              ]
        },
    InheritedRole
      InheritedRoleDetails
        { inheritedRoleName = "hr_manager",
          inheritedRoleRoleSet = ["all_managers", "manager_employee_private_info"]
        }
  ]

--------------------------------------------------------------------------------
-- Tests

tests :: SpecWith TestEnvironment
tests = do
  describe "Redaction in column selection sets" $ do
    it "Check redaction in regular queries" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee(order_by: { id: asc }) {
                    id
                    first_name
                    last_name
                    monthly_salary
                    yearly_salary
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column & yearly_salary computed field,
          -- but the 'employee_private_info' role does, but only for the current
          -- employee's record (ie. hers)
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee:
                - id: 1
                  first_name: David
                  last_name: Holden
                  monthly_salary: null
                  yearly_salary: null
                - id: 2
                  first_name: Grant
                  last_name: Smith
                  monthly_salary: null
                  yearly_salary: null
                - id: 3
                  first_name: Xin
                  last_name: Cheng
                  monthly_salary: 5500
                  yearly_salary: 66000
                - id: 4
                  first_name: Sarah
                  last_name: Smith
                  monthly_salary: null
                  yearly_salary: null
            |]

      shouldReturnYaml testEnvironment actual expected

    it "Check column redaction in nodes in aggregate queries" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee_aggregate(order_by: { id: asc }) {
                    nodes {
                      id
                      first_name
                      last_name
                      monthly_salary
                      yearly_salary
                    }
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column & yearly_salary computed field,
          -- but the 'employee_private_info' role does, but only for the current
          -- employee's record (ie. hers)
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee_aggregate:
                  nodes:
                  - id: 1
                    first_name: David
                    last_name: Holden
                    monthly_salary: null
                    yearly_salary: null
                  - id: 2
                    first_name: Grant
                    last_name: Smith
                    monthly_salary: null
                    yearly_salary: null
                  - id: 3
                    first_name: Xin
                    last_name: Cheng
                    monthly_salary: 5500
                    yearly_salary: 66000
                  - id: 4
                    first_name: Sarah
                    last_name: Smith
                    monthly_salary: null
                    yearly_salary: null
            |]

      shouldReturnYaml testEnvironment actual expected

  describe "Redaction in aggregation calculations" $ do
    it "Check redaction of input values to aggregation functions" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee_aggregate {
                    aggregate {
                      count
                      sum {
                        monthly_salary
                        yearly_salary
                      }
                    }
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column & yearly_salary computed field,
          -- but the 'employee_private_info' role does, but only for the current
          -- employee's record (ie. hers)
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee_aggregate:
                  aggregate:
                    count: 4
                    sum:
                      monthly_salary: 5500
                      yearly_salary: 66000
            |]

      shouldReturnYaml testEnvironment actual expected

    it "Check redaction of input values to count aggregations that use columns" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee_aggregate {
                    aggregate {
                      count
                      count_distinct_salary: count(distinct: true, columns:[monthly_salary])
                      count_not_distinct_salary: count(distinct: false, columns:[monthly_salary])
                    }
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column & yearly_salary computed field,
          -- but the 'employee_private_info' role does, but only for the current
          -- employee's record (ie. hers)
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee_aggregate:
                  aggregate:
                    count: 4
                    count_distinct_salary: 1
                    count_not_distinct_salary: 1
            |]

      shouldReturnYaml testEnvironment actual expected

  describe "Redaction in ordering and distinct on" $ do
    it "ordering by column is applied over redacted column value" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee(order_by: [{ monthly_salary: desc }, {id: desc}]) {
                    id
                    first_name
                    last_name
                    monthly_salary
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column, but the 'employee_private_info' role
          -- does, but only for the current employee's record (ie. hers).
          -- This means when she orders by monthly salary, the ordering
          -- should not know the value of any salary other than hers and therefore
          -- should fall back to order by the id since all other salaries should
          -- appear as null.
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee:
                - id: 4
                  first_name: Sarah
                  last_name: Smith
                  monthly_salary: null
                - id: 2
                  first_name: Grant
                  last_name: Smith
                  monthly_salary: null
                - id: 1
                  first_name: David
                  last_name: Holden
                  monthly_salary: null
                - id: 3
                  first_name: Xin
                  last_name: Cheng
                  monthly_salary: 5500
            |]

      shouldReturnYaml testEnvironment actual expected

    it "ordering by a computed field is applied over redacted computed field value" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee(order_by: [{ yearly_salary: desc }, {id: desc}]) {
                    id
                    first_name
                    last_name
                    yearly_salary
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column, but the 'employee_private_info' role
          -- does, but only for the current employee's record (ie. hers).
          -- This means when she orders by monthly salary, the ordering
          -- should not know the value of any salary other than hers and therefore
          -- should fall back to order by the id since all other salaries should
          -- appear as null.
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee:
                - id: 4
                  first_name: Sarah
                  last_name: Smith
                  yearly_salary: null
                - id: 2
                  first_name: Grant
                  last_name: Smith
                  yearly_salary: null
                - id: 1
                  first_name: David
                  last_name: Holden
                  yearly_salary: null
                - id: 3
                  first_name: Xin
                  last_name: Cheng
                  yearly_salary: 66000
            |]

      shouldReturnYaml testEnvironment actual expected

    it "ordering by aggregate is applied over the aggregate over the redacted column value" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "hr_manager"),
                ("X-Hasura-Manager-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_manager(order_by: [{employees_by_id_to_engineering_manager_id_aggregate: { sum: { monthly_salary: desc } }}, {id: asc}]) {
                    id
                    first_name
                    last_name
                    employees_by_id_to_engineering_manager_id_aggregate {
                      aggregate {
                        sum {
                          monthly_salary
                        }
                      }
                    }
                  }
                }
              |]

          -- Althea Weiss can only see the salaries of the employees she is HR manager for.
          -- This is because the 'manager_employee_private_info' role provides access to the salary
          -- for the current manager's HR-managed employees, but the rest of the employees
          -- are accessed via 'all_managers', which does not expose 'monthly_salary'.
          -- So when Althea orders all managers by the sum of the salary of the employees they
          -- are the _engineering manager_ for, she should only be ordering them by
          -- aggregate of the salaries she can see.
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_manager:
                - id: 3
                  first_name: Althea
                  last_name: Weiss
                  employees_by_id_to_engineering_manager_id_aggregate:
                    aggregate:
                      sum:
                        monthly_salary: null
                - id: 4
                  first_name: Bec
                  last_name: Vo
                  employees_by_id_to_engineering_manager_id_aggregate:
                    aggregate:
                      sum:
                        monthly_salary: null
                - id: 2
                  first_name: Martin
                  last_name: Graham
                  employees_by_id_to_engineering_manager_id_aggregate:
                    aggregate:
                      sum:
                        monthly_salary: 5500
                - id: 1
                  first_name: Ryan
                  last_name: Ray
                  employees_by_id_to_engineering_manager_id_aggregate:
                    aggregate:
                      sum:
                        monthly_salary: 5000
            |]

      shouldReturnYaml testEnvironment actual expected

    it "distinct_on is applied over redacted column values" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "hr_manager"),
                ("X-Hasura-Manager-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee(distinct_on: [nationality], order_by: [{nationality: asc}, {id: asc}]) {
                    id
                    first_name
                    last_name
                    nationality
                  }
                }
              |]

          -- Althea Weiss can only see the nationality of the employees she is HR manager for.
          -- This is because the 'manager_employee_private_info' role provides access to the nationality
          -- for the current manager's HR-managed employees, but the rest of the employees
          -- are accessed via 'all_managers', which does not expose 'nationality'.
          -- So when Althea performs a distinct_on nationality, the distinct should be done over the
          -- values of nationality after redaction, so only the first redacted nationality row gets kept
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee:
                - id: 1
                  first_name: David
                  last_name: Holden
                  nationality: Australian
                - id: 3
                  first_name: Xin
                  last_name: Cheng
                  nationality: Chinese
                - id: 2
                  first_name: Grant
                  last_name: Smith
                  nationality: null
            |]

      shouldReturnYaml testEnvironment actual expected

  describe "Redaction in filtering" $ do
    it "filtering by column is applied against redacted column value" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee(where: { monthly_salary: { _eq: 5000 } }) {
                    id
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the monthly_salary column, but the 'employee_private_info' role
          -- does, but only for the current employee's record (ie. hers).
          -- This means she should not be able to compare against salaries
          -- she does not have access to, such as David Holden's salary
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee: []
            |]

      shouldReturnYaml testEnvironment actual expected

    it "filtering by computed field is applied against redacted computed field value" \testEnvironment -> do
      let schemaName = Schema.getSchemaName testEnvironment
          actual :: IO Value
          actual =
            GraphqlEngine.postGraphqlWithHeaders
              testEnvironment
              [ ("X-Hasura-Role", "employee"),
                ("X-Hasura-Employee-Id", "3")
              ]
              [graphql|
                query {
                  #{schemaName}_employee(where: { yearly_salary: { _eq: 60000 } }) {
                    id
                  }
                }
              |]

          -- Xin Cheng can see her own salary, but not her peers' because the
          -- 'employee_public_info' role does not provide access to
          -- the yearly_salary computed field, but the 'employee_private_info' role
          -- does, but only for the current employee's record (ie. hers).
          -- This means she should not be able to compare against salaries
          -- she does not have access to, such as David Holden's salary
          expected :: Value
          expected =
            [interpolateYaml|
              data:
                #{schemaName}_employee: []
            |]

      shouldReturnYaml testEnvironment actual expected
