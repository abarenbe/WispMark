import React from 'react';

export interface TagPillProps {
  tag: string;
  onClick?: (tag: string) => void;
  onRemove?: (tag: string) => void;
  isRemovable?: boolean;
  size?: 'small' | 'medium' | 'large';
}

export const TagPill: React.FC<TagPillProps> = ({
  tag,
  onClick,
  onRemove,
  isRemovable = false,
  size = 'medium',
}) => {
  const sizeStyles = {
    small: {
      fontSize: '11px',
      padding: '4px 8px',
    },
    medium: {
      fontSize: '13px',
      padding: '6px 10px',
    },
    large: {
      fontSize: '14px',
      padding: '8px 12px',
    },
  };

  const handleClick = (e: React.MouseEvent) => {
    if (onClick) {
      e.preventDefault();
      onClick(tag);
    }
  };

  const handleRemove = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onRemove) {
      onRemove(tag);
    }
  };

  return (
    <div
      className="tag-pill"
      onClick={handleClick}
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: '4px',
        backgroundColor: 'var(--tag-background, rgba(34, 197, 94, 0.2))',
        color: 'var(--tag-color, #22c55e)',
        borderRadius: '16px',
        fontWeight: 500,
        cursor: onClick ? 'pointer' : 'default',
        userSelect: 'none',
        transition: 'all 0.2s ease',
        ...sizeStyles[size],
      }}
      onMouseEnter={(e) => {
        if (onClick) {
          e.currentTarget.style.backgroundColor = 'var(--tag-background-hover, rgba(34, 197, 94, 0.3))';
        }
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.backgroundColor = 'var(--tag-background, rgba(34, 197, 94, 0.2))';
      }}
    >
      <span>#{tag}</span>
      {isRemovable && (
        <button
          onClick={handleRemove}
          className="tag-remove-button"
          style={{
            background: 'none',
            border: 'none',
            color: 'inherit',
            cursor: 'pointer',
            padding: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: '16px',
            height: '16px',
            borderRadius: '50%',
            fontSize: '12px',
            opacity: 0.7,
            transition: 'opacity 0.2s ease',
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.opacity = '1';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.opacity = '0.7';
          }}
          aria-label={`Remove tag ${tag}`}
        >
          ×
        </button>
      )}
    </div>
  );
};

export default TagPill;
