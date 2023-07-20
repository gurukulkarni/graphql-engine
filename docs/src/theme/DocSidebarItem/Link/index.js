import React from 'react';
import clsx from 'clsx';
import { ThemeClassNames } from '@docusaurus/theme-common';
import { isActiveSidebarItem } from '@docusaurus/theme-common/internal';
import Link from '@docusaurus/Link';
import isInternalUrl from '@docusaurus/isInternalUrl';
import IconExternalLink from '@theme/Icon/ExternalLink';
import styles from './styles.module.scss';
import { useColorMode } from '@docusaurus/theme-common';
import EnterpriseLight from '@site/static/icons/enterprise-dark.svg';
import EnterpriseDark from '@site/static/icons/enterprise-light.svg';
import CloudLight from '@site/static/icons/cloud-dark.svg';
import CloudDark from '@site/static/icons/cloud-light.svg';
import BetaTag from '@site/src/components/BetaTag/BetaTag';

export default function DocSidebarItemLink({ item, onItemClick, activePath, level, index, ...props }) {
  const { href, label, className, autoAddBaseUrl } = item;
  const isActive = isActiveSidebarItem(item, activePath);
  const isInternalLink = isInternalUrl(href);
  const { colorMode } = useColorMode();

  const isDarkMode = colorMode === 'dark';

  const enterpriseIcon = isDarkMode ? <EnterpriseDark/> : <EnterpriseLight/>;
  const cloudIcon = isDarkMode ? <CloudDark/> : <CloudLight/>;
  const betaIcon = <BetaTag/>;

  // Conditional rendering for sidebar icons
  let icons;
  switch (className) {
    case 'enterprise-icon':
      icons = enterpriseIcon;
      break;
    case 'cloud-icon':
      icons = cloudIcon;
      break;
    case 'enterprise-icon-and-beta':
      icons = (
          <>
            {enterpriseIcon} {betaIcon}
          </>
      )
      break;
    case 'cloud-and-enterprise-icon':
      icons = (
          <>
            {cloudIcon} {enterpriseIcon}
          </>
      )
      break;
    case 'beta-icon':
      icons = betaIcon;
      break;
  }

  const labelWithIcons = (
      <div className={styles['sidebar_link_wrapper']}>
        {label} {icons}
      </div>
  );

  return (
      <li
          className={clsx(
              ThemeClassNames.docs.docSidebarItemLink,
              ThemeClassNames.docs.docSidebarItemLinkLevel(level),
              'menu__list-item',
              className,
              styles[`sidebar_link_wrapper`]
          )}
          key={label}
      >
        {className !== 'sidebar_heading' ?
            <Link
                className={clsx('menu__link', !isInternalLink && styles.menuExternalLink, {
                  'menu__link--active': isActive,
                })}
                autoAddBaseUrl={autoAddBaseUrl}
                aria-current={isActive ? 'page' : undefined}
                to={href}
                {...(isInternalLink && {
                  onClick: onItemClick ? () => onItemClick(item) : undefined,
                })}
                {...props}
            >
              {labelWithIcons}
            </Link>
            :
            <>
              {labelWithIcons}
            </>
        }
      </li>
  );
}
