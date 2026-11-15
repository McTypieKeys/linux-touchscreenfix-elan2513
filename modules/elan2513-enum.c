// SPDX-License-Identifier: GPL-2.0-only
/*
 * HP Pavilion ELAN2513 ACPI enumeration-state workaround.
 * Changes the in-kernel enumeration state, NOT the firmware ACPI tables.
 * Only supports the tested ACPI path, and keeps the device referenced.
 */
#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/errno.h>
#include <linux/string.h>
#include <linux/acpi.h>
#include <acpi/acpi_bus.h>

#define ELAN_ACPI_PATH "\\_SB_.PC00.I2C0.TPL1"

static struct acpi_device *elan_adev;
static u8 previous_enum_state;

static int __init elan2513_enum_init(void)
{
    struct acpi_device *adev;
    struct acpi_buffer path = { ACPI_ALLOCATE_BUFFER, NULL };
    acpi_status status;

    adev = acpi_dev_get_first_match_dev("ELAN2513", NULL, -1);
    if (!adev) {
        pr_err("elan2513-enum: ACPI ELAN2513 device missing\n");
        return -ENODEV;
    }

    status = acpi_get_name(acpi_device_handle(adev), ACPI_FULL_PATHNAME, &path);
    if (ACPI_FAILURE(status) || !path.pointer ||
        strcmp(path.pointer, ELAN_ACPI_PATH)) {
        pr_err("elan2513-enum: unexpected ACPI path; refusing to modify\n");
        ACPI_FREE(path.pointer);
        acpi_dev_put(adev);
        return -ENODEV;
    }
    ACPI_FREE(path.pointer);

    previous_enum_state = adev->power.state_for_enumeration;
    adev->power.state_for_enumeration = ACPI_STATE_D3_COLD;
    elan_adev = adev;
    pr_info("elan2513-enum: %s enumeration state %u -> D3cold (4)\n",
            ELAN_ACPI_PATH, previous_enum_state);
    return 0;
}

static void __exit elan2513_enum_exit(void)
{
    if (!elan_adev)
        return;
    elan_adev->power.state_for_enumeration = previous_enum_state;
    pr_info("elan2513-enum: restored enumeration state to %u\n",
            previous_enum_state);
    acpi_dev_put(elan_adev);
    elan_adev = NULL;
}

module_init(elan2513_enum_init);
module_exit(elan2513_enum_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Experimental HP ELAN2513 ACPI enumeration-state quirk");
MODULE_AUTHOR("ELAN2513 community workaround contributors");
