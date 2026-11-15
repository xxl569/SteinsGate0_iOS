/*
 * Godot 4.3 纯 C11 GDExtension 绑定层：向 GDScript 暴露 MgsNative 类。
 */

#include "gdextension_interface.h"
#include "mgs_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define GDE_EXPORT __declspec(dllexport)
#else
#define GDE_EXPORT __attribute__((visibility("default")))
#endif

typedef struct { uint64_t opaque[4]; } GdVariant;
typedef struct { uint64_t opaque[2]; } GdOpaque;

typedef struct {
    GDExtensionClassLibraryPtr library;
    GDExtensionInterfaceMemAlloc mem_alloc;
    GDExtensionInterfaceMemFree mem_free;
    GDExtensionInterfaceClassdbRegisterExtensionClass3 register_class3;
    GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
    GDExtensionInterfaceClassdbConstructObject construct_object;
    GDExtensionInterfaceObjectSetInstance object_set_instance;
    GDExtensionInterfaceObjectSetInstanceBinding object_set_instance_binding;

    GDExtensionInterfaceStringNewWithUtf8Chars string_new_utf8;
    GDExtensionInterfaceStringToUtf8Chars string_to_utf8;
    GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new_latin1;

    GDExtensionInterfaceVariantNewNil variant_new_nil;
    GDExtensionInterfaceVariantDestroy variant_destroy;
    GDExtensionInterfaceVariantCall variant_call;
    GDExtensionInterfaceGetVariantFromTypeConstructor get_from_type;
    GDExtensionInterfaceGetVariantToTypeConstructor get_to_type;

    GDExtensionInterfaceVariantGetPtrConstructor get_ptr_ctor;
    GDExtensionInterfaceVariantGetPtrDestructor get_ptr_dtor;
    GDExtensionInterfaceVariantGetPtrBuiltinMethod get_ptr_builtin_method;

    GDExtensionInterfacePackedByteArrayOperatorIndex pba_index;
    GDExtensionInterfacePackedByteArrayOperatorIndexConst pba_index_const;
    GDExtensionInterfacePackedInt32ArrayOperatorIndexConst pi32_index_const;
    GDExtensionInterfacePackedStringArrayOperatorIndex psa_index;
    GDExtensionInterfaceDictionaryOperatorIndex dict_index;
    GDExtensionInterfaceArrayOperatorIndex array_index;

    GDExtensionVariantFromTypeConstructorFunc from_type[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
    GDExtensionTypeFromVariantConstructorFunc to_type[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
    GDExtensionPtrConstructor ctor_default[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];
    GDExtensionPtrDestructor dtor[GDEXTENSION_VARIANT_TYPE_VARIANT_MAX];

    GDExtensionPtrBuiltInMethod pba_resize;
    GDExtensionPtrBuiltInMethod psa_resize;
    GDExtensionPtrBuiltInMethod array_resize;
} MgsApi;

static MgsApi g_api;
static const GDExtensionInstanceBindingCallbacks g_binding_callbacks = {NULL, NULL, NULL};

typedef struct {
    GDExtensionObjectPtr godot_obj;
    MgsVfsState vfs;
} MgsNativeInstance;

/* ==================== Variant 辅助函数 ==================== */

static void var_set_bool(GDExtensionVariantPtr dst, GDExtensionBool v) {
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_BOOL](dst, &v);
}

static void var_set_int(GDExtensionVariantPtr dst, int64_t v) {
    GDExtensionInt gv = (GDExtensionInt)v;
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_INT](dst, &gv);
}

static void var_set_string(GDExtensionVariantPtr dst, const char *utf8) {
    GdOpaque s = {0};
    g_api.string_new_utf8(&s, utf8 ? utf8 : "");
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_STRING](dst, &s);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](&s);
}

static char *var_to_cstr(GDExtensionConstVariantPtr v) {
    GdOpaque s = {0};
    g_api.to_type[GDEXTENSION_VARIANT_TYPE_STRING](&s, (GDExtensionVariantPtr)v);
    GDExtensionInt len = g_api.string_to_utf8(&s, NULL, 0);
    if (len < 0) len = 0;
    char *buf = (char *)malloc((size_t)len + 1);
    if (buf) {
        if (len > 0) g_api.string_to_utf8(&s, buf, len);
        buf[len] = '\0';
    }
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](&s);
    return buf;
}

static int64_t var_to_int(GDExtensionConstVariantPtr v) {
    GDExtensionInt gv = 0;
    g_api.to_type[GDEXTENSION_VARIANT_TYPE_INT](&gv, (GDExtensionVariantPtr)v);
    return (int64_t)gv;
}

static int var_to_bool(GDExtensionConstVariantPtr v) {
    GDExtensionBool bv = 0;
    g_api.to_type[GDEXTENSION_VARIANT_TYPE_BOOL](&bv, (GDExtensionVariantPtr)v);
    return bv ? 1 : 0;
}

static int64_t var_call_size(GDExtensionConstVariantPtr v) {
    GdOpaque m_size = {0};
    g_api.string_name_new_latin1(&m_size, "size", 0);
    GdVariant ret = {0};
    g_api.variant_new_nil(&ret);
    GDExtensionCallError err = {0};
    g_api.variant_call((GDExtensionVariantPtr)v, &m_size, NULL, 0, &ret, &err);
    int64_t sz = (err.error == GDEXTENSION_CALL_OK) ? var_to_int(&ret) : 0;
    g_api.variant_destroy(&ret);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&m_size);
    return sz;
}

static void var_set_pba(GDExtensionVariantPtr dst, const uint8_t *bytes, size_t len) {
    GdOpaque pba = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&pba, NULL);
    if (len > 0 && bytes) {
        GDExtensionInt n = (GDExtensionInt)len;
        const GDExtensionConstTypePtr args[1] = {&n};
        GDExtensionInt rc = 0;
        g_api.pba_resize(&pba, args, &rc, 0);
        uint8_t *ptr = g_api.pba_index(&pba, 0);
        if (ptr) memcpy(ptr, bytes, len);
    }
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](dst, &pba);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&pba);
}

static void dict_set_int(GdOpaque *dict, const char *key, int64_t val) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_int(slot, val);
    g_api.variant_destroy(&k);
}

static void dict_set_bool(GdOpaque *dict, const char *key, int val) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_bool(slot, val ? 1 : 0);
    g_api.variant_destroy(&k);
}

static void dict_set_str(GdOpaque *dict, const char *key, const char *val) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_string(slot, val);
    g_api.variant_destroy(&k);
}

static void dict_set_pba(GdOpaque *dict, const char *key, const uint8_t *bytes, size_t len) {
    GdVariant k = {0};
    var_set_string(&k, key);
    GDExtensionVariantPtr slot = g_api.dict_index(dict, &k);
    if (slot) var_set_pba(slot, bytes, len);
    g_api.variant_destroy(&k);
}

/* ==================== 类实例生命周期 ==================== */

static GDExtensionObjectPtr mgs_native_create_instance(void *p_userdata) {
    (void)p_userdata;
    GdOpaque parent_sn = {0};
    GdOpaque self_sn = {0};
    g_api.string_name_new_latin1(&parent_sn, "RefCounted", 0);
    g_api.string_name_new_latin1(&self_sn, "MgsNative", 0);

    GDExtensionObjectPtr obj = g_api.construct_object(&parent_sn);
    MgsNativeInstance *inst = (MgsNativeInstance *)g_api.mem_alloc(sizeof(MgsNativeInstance));
    memset(inst, 0, sizeof(*inst));
    inst->godot_obj = obj;
    mgs_vfs_init(&inst->vfs);

    g_api.object_set_instance(obj, &self_sn, inst);
    g_api.object_set_instance_binding(obj, g_api.library, inst, &g_binding_callbacks);

    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&parent_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&self_sn);
    return obj;
}

static void mgs_native_free_instance(void *p_userdata, GDExtensionClassInstancePtr p_instance) {
    (void)p_userdata;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    if (inst) {
        mgs_vfs_free(&inst->vfs);
        g_api.mem_free(inst);
    }
}

/* ==================== 暴露给 GDScript 的方法 ==================== */

static void m_mount_game_dir(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    if (!inst || p_arg_count < 1) {
        var_set_int(r_ret, -1);
        return;
    }
    char *dir = var_to_cstr(p_args[0]);
    int32_t rc = mgs_vfs_mount(&inst->vfs, dir ? dir : "");
    free(dir);
    var_set_int(r_ret, rc);
}

static void m_reset(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_args; (void)p_arg_count; (void)r_ret;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    if (inst) {
        mgs_vfs_free(&inst->vfs);
        mgs_vfs_init(&inst->vfs);
    }
}

static void m_get_archive_count(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_args; (void)p_arg_count;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    var_set_int(r_ret, inst ? (int64_t)inst->vfs.archive_count : 0);
}

static void m_get_entry_count(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_args; (void)p_arg_count;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    var_set_int(r_ret, inst ? (int64_t)inst->vfs.total_entries : 0);
}

static void m_list_archives(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_args; (void)p_arg_count;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;

    GdOpaque psa = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](&psa, NULL);
    if (inst && inst->vfs.archive_count > 0) {
        GDExtensionInt n = (GDExtensionInt)inst->vfs.archive_count;
        const GDExtensionConstTypePtr args[1] = {&n};
        GDExtensionInt rc = 0;
        g_api.psa_resize(&psa, args, &rc, 0);
        for (uint32_t i = 0; i < inst->vfs.archive_count; i++) {
            GDExtensionStringPtr sp = g_api.psa_index(&psa, (GDExtensionInt)i);
            g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](sp);
            g_api.string_new_utf8(sp, inst->vfs.archives[i].archive_name);
        }
    }
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](r_ret, &psa);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](&psa);
}

static void m_list_entries(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    char *arch_name = (p_arg_count >= 1) ? var_to_cstr(p_args[0]) : NULL;
    char *prefix = (p_arg_count >= 2) ? var_to_cstr(p_args[1]) : NULL;
    size_t plen = prefix ? strlen(prefix) : 0;
    for (size_t i = 0; i < plen; i++) {
        if (prefix[i] >= 'A' && prefix[i] <= 'Z') prefix[i] = (char)(prefix[i] - 'A' + 'a');
    }

    uint32_t match_cnt = 0;
    const MgsArchive *target_arch = NULL;
    if (inst) {
        if (arch_name && arch_name[0]) {
            target_arch = mgs_vfs_find_archive(&inst->vfs, arch_name);
            if (target_arch) {
                for (uint32_t i = 0; i < target_arch->count; i++) {
                    if (plen == 0 || strncmp(target_arch->entries[i].name_lower, prefix, plen) == 0) {
                        match_cnt++;
                    }
                }
            }
        } else {
            for (uint32_t a = 0; a < inst->vfs.archive_count; a++) {
                const MgsArchive *ar = &inst->vfs.archives[a];
                for (uint32_t i = 0; i < ar->count; i++) {
                    if (plen == 0 || strncmp(ar->entries[i].name_lower, prefix, plen) == 0) {
                        match_cnt++;
                    }
                }
            }
        }
    }

    GdOpaque psa = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](&psa, NULL);
    if (match_cnt > 0) {
        GDExtensionInt n = (GDExtensionInt)match_cnt;
        const GDExtensionConstTypePtr args[1] = {&n};
        GDExtensionInt rc = 0;
        g_api.psa_resize(&psa, args, &rc, 0);
        uint32_t wi = 0;
        if (target_arch) {
            for (uint32_t i = 0; i < target_arch->count; i++) {
                if (plen == 0 || strncmp(target_arch->entries[i].name_lower, prefix, plen) == 0) {
                    GDExtensionStringPtr sp = g_api.psa_index(&psa, (GDExtensionInt)wi++);
                    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](sp);
                    g_api.string_new_utf8(sp, target_arch->entries[i].name);
                }
            }
        } else {
            for (uint32_t a = 0; a < inst->vfs.archive_count; a++) {
                const MgsArchive *ar = &inst->vfs.archives[a];
                for (uint32_t i = 0; i < ar->count; i++) {
                    if (plen == 0 || strncmp(ar->entries[i].name_lower, prefix, plen) == 0) {
                        char combined[300];
                        snprintf(combined, sizeof(combined), "%s:%s", ar->archive_name, ar->entries[i].name);
                        GDExtensionStringPtr sp = g_api.psa_index(&psa, (GDExtensionInt)wi++);
                        g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](sp);
                        g_api.string_new_utf8(sp, combined);
                    }
                }
            }
        }
    }

    free(arch_name);
    free(prefix);
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](r_ret, &psa);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY](&psa);
}

static void m_has_entry(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    if (!inst || p_arg_count < 2) {
        var_set_bool(r_ret, 0);
        return;
    }
    char *arch = var_to_cstr(p_args[0]);
    char *entry = var_to_cstr(p_args[1]);
    const MgsEntry *e = (arch && entry) ? mgs_vfs_find_entry(&inst->vfs, arch, entry) : NULL;
    free(arch);
    free(entry);
    var_set_bool(r_ret, e != NULL ? 1 : 0);
}

static void m_get_entry_info(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;

    GdOpaque dict = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict, NULL);
    if (!inst || p_arg_count < 2) {
        dict_set_bool(&dict, "ok", 0);
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
        return;
    }
    char *arch = var_to_cstr(p_args[0]);
    char *entry_name = var_to_cstr(p_args[1]);
    const MgsArchive *ar = arch ? mgs_vfs_find_archive(&inst->vfs, arch) : NULL;
    const MgsEntry *e = (arch && entry_name) ? mgs_vfs_find_entry(&inst->vfs, arch, entry_name) : NULL;
    if (ar && e) {
        dict_set_bool(&dict, "ok", 1);
        dict_set_str(&dict, "archive", ar->archive_name);
        dict_set_str(&dict, "name", e->name);
        dict_set_int(&dict, "index", (int64_t)e->index);
        dict_set_int(&dict, "compressed", (int64_t)e->compression);
        dict_set_int(&dict, "size", (int64_t)e->size);
        dict_set_int(&dict, "uncompressed_size", (int64_t)e->uncompressed_size);
    } else {
        dict_set_bool(&dict, "ok", 0);
    }
    free(arch);
    free(entry_name);
    g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
}

static void m_read_entry(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;
    if (!inst || p_arg_count < 2) {
        var_set_pba(r_ret, NULL, 0);
        return;
    }
    char *arch = var_to_cstr(p_args[0]);
    char *entry = var_to_cstr(p_args[1]);
    uint8_t *buf = NULL;
    size_t sz = 0;
    int32_t rc = (arch && entry) ? mgs_vfs_read_entry(&inst->vfs, arch, entry, &buf, &sz) : -1;
    free(arch);
    free(entry);
    if (rc == 0 && buf) {
        var_set_pba(r_ret, buf, sz);
        free(buf);
    } else {
        var_set_pba(r_ret, NULL, 0);
    }
}

static void fill_image_dict(GdOpaque *dict, const MgsDdsImage *img, int32_t rc) {
    if (rc == 0 && img->ok && img->data) {
        dict_set_bool(dict, "ok", 1);
        dict_set_int(dict, "width", (int64_t)img->width);
        dict_set_int(dict, "height", (int64_t)img->height);
        dict_set_str(dict, "format", img->is_png ? "png" : (img->is_l8 ? "l8" : "rgba8"));
        dict_set_pba(dict, "data", img->data, img->data_size);
    } else {
        dict_set_bool(dict, "ok", 0);
        dict_set_int(dict, "error", rc);
    }
}

static void m_decode_image_buffer(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_instance;
    r_err->error = GDEXTENSION_CALL_OK;
    GdOpaque dict = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict, NULL);

    if (p_arg_count < 1) {
        dict_set_bool(&dict, "ok", 0);
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
        return;
    }

    int64_t len = var_call_size(p_args[0]);
    int l8_only = (p_arg_count >= 2) ? var_to_bool(p_args[1]) : 0;
    if (len <= 0) {
        dict_set_bool(&dict, "ok", 0);
        dict_set_int(&dict, "error", -1);
    } else {
        GdOpaque pba = {0};
        g_api.to_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&pba, (GDExtensionVariantPtr)p_args[0]);
        const uint8_t *ptr = g_api.pba_index_const(&pba, 0);
        MgsDdsImage img = {0};
        int32_t rc = ptr ? mgs_decode_image_buffer(ptr, (size_t)len, l8_only, &img) : -2;
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&pba);
        fill_image_dict(&dict, &img, rc);
        mgs_free_image(&img);
    }

    g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
}

static void m_decode_archive_image(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata;
    r_err->error = GDEXTENSION_CALL_OK;
    MgsNativeInstance *inst = (MgsNativeInstance *)p_instance;

    GdOpaque dict = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict, NULL);
    if (!inst || p_arg_count < 2) {
        dict_set_bool(&dict, "ok", 0);
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
        return;
    }

    char *arch = var_to_cstr(p_args[0]);
    char *entry = var_to_cstr(p_args[1]);
    int l8_only = (p_arg_count >= 3) ? var_to_bool(p_args[2]) : 0;

    uint8_t *buf = NULL;
    size_t sz = 0;
    int32_t rc = (arch && entry) ? mgs_vfs_read_entry(&inst->vfs, arch, entry, &buf, &sz) : -1;
    free(arch);
    free(entry);

    if (rc == 0 && buf && sz > 0) {
        MgsDdsImage img = {0};
        int32_t drc = mgs_decode_image_buffer(buf, sz, l8_only, &img);
        free(buf);
        fill_image_dict(&dict, &img, drc);
        mgs_free_image(&img);
    } else {
        free(buf);
        dict_set_bool(&dict, "ok", 0);
        dict_set_int(&dict, "error", rc);
    }

    g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
}

static void m_compose_lay_rgba(
    void *p_userdata, GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_arg_count,
    GDExtensionVariantPtr r_ret, GDExtensionCallError *r_err
) {
    (void)p_userdata; (void)p_instance;
    r_err->error = GDEXTENSION_CALL_OK;

    GdOpaque dict = {0};
    g_api.ctor_default[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict, NULL);
    if (p_arg_count < 5) {
        dict_set_bool(&dict, "ok", 0);
        dict_set_int(&dict, "error", -1);
        g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
        return;
    }

    int64_t lay_len = var_call_size(p_args[0]);
    int64_t atlas_len = var_call_size(p_args[1]);
    int32_t aw = (int32_t)var_to_int(p_args[2]);
    int32_t ah = (int32_t)var_to_int(p_args[3]);
    int64_t g_cnt = var_call_size(p_args[4]);

    if (lay_len < 8 || aw <= 0 || ah <= 0 || atlas_len < (int64_t)aw * ah * 4 || g_cnt <= 0) {
        dict_set_bool(&dict, "ok", 0);
        dict_set_int(&dict, "error", -2);
    } else {
        GdOpaque lay_pba = {0}, atlas_pba = {0}, grp_pia = {0};
        g_api.to_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&lay_pba, (GDExtensionVariantPtr)p_args[0]);
        g_api.to_type[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&atlas_pba, (GDExtensionVariantPtr)p_args[1]);
        g_api.to_type[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](&grp_pia, (GDExtensionVariantPtr)p_args[4]);

        const uint8_t *lay_ptr = g_api.pba_index_const(&lay_pba, 0);
        const uint8_t *atlas_ptr = g_api.pba_index_const(&atlas_pba, 0);
        const int32_t *grp_ptr = g_api.pi32_index_const(&grp_pia, 0);

        MgsLayResult res = {0};
        int32_t rc = (lay_ptr && atlas_ptr && grp_ptr)
            ? mgs_compose_lay_rgba(lay_ptr, (size_t)lay_len, atlas_ptr, aw, ah, grp_ptr, (int32_t)g_cnt, &res)
            : -3;

        g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&lay_pba);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY](&atlas_pba);
        g_api.dtor[GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY](&grp_pia);

        if (rc == 0 && res.ok && res.rgba) {
            dict_set_bool(&dict, "ok", 1);
            dict_set_int(&dict, "width", (int64_t)res.width);
            dict_set_int(&dict, "height", (int64_t)res.height);
            dict_set_int(&dict, "origin_x", (int64_t)res.origin_x);
            dict_set_int(&dict, "origin_y", (int64_t)res.origin_y);
            dict_set_pba(&dict, "data", res.rgba, res.rgba_size);
        } else {
            dict_set_bool(&dict, "ok", 0);
            dict_set_int(&dict, "error", rc);
        }
        mgs_free_lay(&res);
    }

    g_api.from_type[GDEXTENSION_VARIANT_TYPE_DICTIONARY](r_ret, &dict);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_DICTIONARY](&dict);
}

/* ==================== 方法注册与模块入口 ==================== */

static void reg_method(
    const char *cls_name,
    const char *method_name,
    GDExtensionClassMethodCall call_fn,
    GDExtensionVariantType ret_type,
    uint32_t arg_count,
    const GDExtensionVariantType *arg_types,
    uint32_t default_count,
    GDExtensionVariantPtr *default_vals
) {
    GdOpaque cls_sn = {0}, m_sn = {0};
    g_api.string_name_new_latin1(&cls_sn, cls_name, 0);
    g_api.string_name_new_latin1(&m_sn, method_name, 0);

    GdOpaque empty_sn = {0};
    g_api.string_name_new_latin1(&empty_sn, "", 0);
    GdOpaque empty_str = {0};
    g_api.string_new_utf8(&empty_str, "");

    GDExtensionPropertyInfo ret_info = {0};
    ret_info.type = ret_type;
    ret_info.name = &empty_sn;
    ret_info.class_name = &empty_sn;
    ret_info.hint_string = &empty_str;

    GDExtensionPropertyInfo args_info[8];
    GDExtensionClassMethodArgumentMetadata args_meta[8];
    memset(args_info, 0, sizeof(args_info));
    memset(args_meta, 0, sizeof(args_meta));
    for (uint32_t i = 0; i < arg_count && i < 8; i++) {
        args_info[i].type = arg_types[i];
        args_info[i].name = &empty_sn;
        args_info[i].class_name = &empty_sn;
        args_info[i].hint_string = &empty_str;
    }

    GDExtensionClassMethodInfo mi = {0};
    mi.name = &m_sn;
    mi.call_func = call_fn;
    mi.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT;
    mi.has_return_value = (ret_type != GDEXTENSION_VARIANT_TYPE_NIL) ? 1 : 0;
    mi.return_value_info = &ret_info;
    mi.argument_count = arg_count;
    mi.arguments_info = arg_count ? args_info : NULL;
    mi.arguments_metadata = arg_count ? args_meta : NULL;
    mi.default_argument_count = default_count;
    mi.default_arguments = default_vals;

    g_api.register_method(g_api.library, &cls_sn, &mi);

    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING](&empty_str);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&empty_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&m_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&cls_sn);
}

static void initialize_mgs_module(void *userdata, GDExtensionInitializationLevel p_level) {
    (void)userdata;
    if (p_level != GDEXTENSION_INITIALIZATION_SCENE) return;

    GdOpaque cls_sn = {0}, parent_sn = {0};
    g_api.string_name_new_latin1(&cls_sn, "MgsNative", 0);
    g_api.string_name_new_latin1(&parent_sn, "RefCounted", 0);

    GDExtensionClassCreationInfo3 ci = {0};
    ci.is_exposed = 1;
    ci.create_instance_func = mgs_native_create_instance;
    ci.free_instance_func = mgs_native_free_instance;
    g_api.register_class3(g_api.library, &cls_sn, &parent_sn, &ci);

    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&parent_sn);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&cls_sn);

    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING};
        reg_method("MgsNative", "mount_game_dir", m_mount_game_dir, GDEXTENSION_VARIANT_TYPE_INT, 1, args, 0, NULL);
    }
    reg_method("MgsNative", "reset", m_reset, GDEXTENSION_VARIANT_TYPE_NIL, 0, NULL, 0, NULL);
    reg_method("MgsNative", "get_archive_count", m_get_archive_count, GDEXTENSION_VARIANT_TYPE_INT, 0, NULL, 0, NULL);
    reg_method("MgsNative", "get_entry_count", m_get_entry_count, GDEXTENSION_VARIANT_TYPE_INT, 0, NULL, 0, NULL);
    reg_method("MgsNative", "list_archives", m_list_archives, GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY, 0, NULL, 0, NULL);

    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_STRING};
        GdVariant def0 = {0}, def1 = {0};
        var_set_string(&def0, "");
        var_set_string(&def1, "");
        GDExtensionVariantPtr defs[] = {&def0, &def1};
        reg_method("MgsNative", "list_entries", m_list_entries, GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY, 2, args, 2, defs);
        g_api.variant_destroy(&def0);
        g_api.variant_destroy(&def1);
    }
    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_STRING, GDEXTENSION_VARIANT_TYPE_STRING};
        reg_method("MgsNative", "has_entry", m_has_entry, GDEXTENSION_VARIANT_TYPE_BOOL, 2, args, 0, NULL);
        reg_method("MgsNative", "get_entry_info", m_get_entry_info, GDEXTENSION_VARIANT_TYPE_DICTIONARY, 2, args, 0, NULL);
        reg_method("MgsNative", "read_entry", m_read_entry, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 2, args, 0, NULL);
    }
    {
        GDExtensionVariantType args[] = {GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, GDEXTENSION_VARIANT_TYPE_BOOL};
        GdVariant def_l8 = {0};
        var_set_bool(&def_l8, 0);
        GDExtensionVariantPtr defs[] = {&def_l8};
        reg_method("MgsNative", "decode_image_buffer", m_decode_image_buffer, GDEXTENSION_VARIANT_TYPE_DICTIONARY, 2, args, 1, defs);
        g_api.variant_destroy(&def_l8);
    }
    {
        GDExtensionVariantType args[] = {
            GDEXTENSION_VARIANT_TYPE_STRING,
            GDEXTENSION_VARIANT_TYPE_STRING,
            GDEXTENSION_VARIANT_TYPE_BOOL
        };
        GdVariant def_l8 = {0};
        var_set_bool(&def_l8, 0);
        GDExtensionVariantPtr defs[] = {&def_l8};
        reg_method("MgsNative", "decode_archive_image", m_decode_archive_image, GDEXTENSION_VARIANT_TYPE_DICTIONARY, 3, args, 1, defs);
        g_api.variant_destroy(&def_l8);
    }
    {
        GDExtensionVariantType args[] = {
            GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
            GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
            GDEXTENSION_VARIANT_TYPE_INT,
            GDEXTENSION_VARIANT_TYPE_INT,
            GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY
        };
        reg_method("MgsNative", "compose_lay_rgba", m_compose_lay_rgba, GDEXTENSION_VARIANT_TYPE_DICTIONARY, 5, args, 0, NULL);
    }
}

static void deinitialize_mgs_module(void *userdata, GDExtensionInitializationLevel p_level) {
    (void)userdata;
    (void)p_level;
}

GDExtensionBool GDE_EXPORT mgs_native_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization *r_initialization
) {
    memset(&g_api, 0, sizeof(g_api));
    g_api.library = p_library;

    #define LOAD_PROC(field, type, name) g_api.field = (type)(void *)p_get_proc_address(name)
    LOAD_PROC(mem_alloc, GDExtensionInterfaceMemAlloc, "mem_alloc");
    LOAD_PROC(mem_free, GDExtensionInterfaceMemFree, "mem_free");
    LOAD_PROC(register_class3, GDExtensionInterfaceClassdbRegisterExtensionClass3, "classdb_register_extension_class3");
    LOAD_PROC(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD_PROC(construct_object, GDExtensionInterfaceClassdbConstructObject, "classdb_construct_object");
    LOAD_PROC(object_set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD_PROC(object_set_instance_binding, GDExtensionInterfaceObjectSetInstanceBinding, "object_set_instance_binding");

    LOAD_PROC(string_new_utf8, GDExtensionInterfaceStringNewWithUtf8Chars, "string_new_with_utf8_chars");
    LOAD_PROC(string_to_utf8, GDExtensionInterfaceStringToUtf8Chars, "string_to_utf8_chars");
    LOAD_PROC(string_name_new_latin1, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");

    LOAD_PROC(variant_new_nil, GDExtensionInterfaceVariantNewNil, "variant_new_nil");
    LOAD_PROC(variant_destroy, GDExtensionInterfaceVariantDestroy, "variant_destroy");
    LOAD_PROC(variant_call, GDExtensionInterfaceVariantCall, "variant_call");
    LOAD_PROC(get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD_PROC(get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");

    LOAD_PROC(get_ptr_ctor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
    LOAD_PROC(get_ptr_dtor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD_PROC(get_ptr_builtin_method, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");

    LOAD_PROC(pba_index, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
    LOAD_PROC(pba_index_const, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
    LOAD_PROC(pi32_index_const, GDExtensionInterfacePackedInt32ArrayOperatorIndexConst, "packed_int32_array_operator_index_const");
    LOAD_PROC(psa_index, GDExtensionInterfacePackedStringArrayOperatorIndex, "packed_string_array_operator_index");
    LOAD_PROC(dict_index, GDExtensionInterfaceDictionaryOperatorIndex, "dictionary_operator_index");
    LOAD_PROC(array_index, GDExtensionInterfaceArrayOperatorIndex, "array_operator_index");
    #undef LOAD_PROC

    for (int t = 1; t < GDEXTENSION_VARIANT_TYPE_VARIANT_MAX; t++) {
        g_api.from_type[t] = g_api.get_from_type((GDExtensionVariantType)t);
        g_api.to_type[t] = g_api.get_to_type((GDExtensionVariantType)t);
        g_api.ctor_default[t] = g_api.get_ptr_ctor((GDExtensionVariantType)t, 0);
        g_api.dtor[t] = g_api.get_ptr_dtor((GDExtensionVariantType)t);
    }

    GdOpaque sn_resize = {0};
    g_api.string_name_new_latin1(&sn_resize, "resize", 0);
    g_api.pba_resize = g_api.get_ptr_builtin_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &sn_resize, 848867239);
    g_api.psa_resize = g_api.get_ptr_builtin_method(GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY, &sn_resize, 848867239);
    g_api.array_resize = g_api.get_ptr_builtin_method(GDEXTENSION_VARIANT_TYPE_ARRAY, &sn_resize, 848867239);
    g_api.dtor[GDEXTENSION_VARIANT_TYPE_STRING_NAME](&sn_resize);

    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    r_initialization->initialize = initialize_mgs_module;
    r_initialization->deinitialize = deinitialize_mgs_module;
    return 1;
}
